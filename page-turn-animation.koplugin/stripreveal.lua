local Device = require("device")
local ffiUtil = require("ffi/util")

local Screen = Device.screen
local StripReveal = {}

local SHAPE_BANDS = 24

-- Right-hand reveal edges sampled from the approved 202x270 reference GIF.
-- Each frame contains one normalized X coordinate (0..1) per horizontal band.
-- The page pixels are NOT scaled or deformed: these values only describe the
-- moving boundary between the old page and the already-rendered new page.
local FLIP_EDGE_KEYFRAMES = {
    {
        0.3814, 0.7027, 0.9055, 0.8993, 0.8955, 0.8905,
        0.8856, 0.8831, 0.8806, 0.8773, 0.8748, 0.8706,
        0.8665, 0.8624, 0.8574, 0.8557, 0.8507, 0.8483,
        0.8458, 0.8445, 0.8408, 0.8188, 0.6464, 0.4453,
    },
    {
        0.3846, 0.6405, 0.7500, 0.7409, 0.7330, 0.7251,
        0.7177, 0.7081, 0.6994, 0.6936, 0.6878, 0.6808,
        0.6766, 0.6725, 0.6683, 0.6633, 0.6617, 0.6600,
        0.6567, 0.6530, 0.6509, 0.6464, 0.5531, 0.3875,
    },
    {
        0.3166, 0.4378, 0.4436, 0.4287, 0.4125, 0.3980,
        0.3868, 0.3740, 0.3624, 0.3520, 0.3416, 0.3329,
        0.3255, 0.3176, 0.3101, 0.3035, 0.2952, 0.2865,
        0.2790, 0.2711, 0.2653, 0.2587, 0.2504, 0.2200,
    },
    {
        0.1990, 0.1953, 0.1882, 0.1816, 0.1737, 0.1679,
        0.1642, 0.1596, 0.1567, 0.1542, 0.1542, 0.1501,
        0.1493, 0.1493, 0.1451, 0.1443, 0.1443, 0.1410,
        0.1393, 0.1393, 0.1405, 0.1443, 0.1443, 0.1443,
    },
}

-- With the default six animation steps, the first four submitted frames land
-- directly on the four traced GIF edges, then the final two frames collapse
-- the remaining edge to the opposite side. Higher step counts interpolate.
local FLIP_EDGE_TIMES = { 0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 1 }

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function nowSeconds()
    local s, us = ffiUtil.gettime()
    return s + us / 1000000
end

local function sleepMs(ms)
    if ms and ms > 0 then
        ffiUtil.usleep(math.floor(ms * 1000))
    end
end

function StripReveal.preflight(config)
    config = config or {}
    local waveform = config.waveform or "auto"
    local shape = config.shape or "straight"
    if waveform == "auto" and not Screen.refreshUI then
        return nil, "AUTO/UI refresh is unavailable on this device."
    elseif waveform == "du" and not Screen.refreshFast then
        return nil, "DU/Fast refresh is unavailable on this device."
    elseif waveform == "a2" and not Screen.refreshA2 then
        return nil, "A2 refresh is unavailable on this device."
    elseif waveform ~= "auto" and waveform ~= "du" and waveform ~= "a2" then
        return nil, "Unknown strip waveform: " .. tostring(waveform)
    end
    if shape ~= "straight" and shape ~= "diagonal"
            and shape ~= "bottom_curve"
            and shape ~= "bottom_curve2"
            and shape ~= "bottom_curve3"
            and shape ~= "page_flip" then
        return nil, "Unknown reveal shape: " .. tostring(shape)
    end
    return true
end

local function waitMarker(marker)
    if marker and Screen.mech_wait_update_complete then
        local ret = Screen:mech_wait_update_complete(marker)
        Screen.dont_wait_for_marker = marker
        return ret
    end
    if Screen.refreshWaitForLast then
        Screen:refreshWaitForLast()
    end
    return 0
end

local function submitRegion(waveform, x, y, w, h)
    if w <= 0 or h <= 0 then return nil end
    local before = Screen.marker
    if waveform == "a2" then
        Screen:refreshA2(x, y, w, h)
    elseif waveform == "du" then
        Screen:refreshFast(x, y, w, h)
    else
        -- Original KPW4 ZIP path. On Kindle Rex KOReader's UI refresh maps
        -- to the AUTO waveform.
        Screen:refreshUI(x, y, w, h)
    end
    if Screen.marker and Screen.marker ~= before then
        return Screen.marker
    end
end

-- Sample one traced edge at an arbitrary vertical position. State 0 is the
-- untouched page edge at x=1; states 1..4 are the GIF samples; state 5 is the
-- completed turn at x=0.
local function sampleFlipEdgeState(state, y_norm)
    if state <= 0 then return 1 end
    if state > #FLIP_EDGE_KEYFRAMES then return 0 end

    local frame = FLIP_EDGE_KEYFRAMES[state]
    local pos = clamp(y_norm, 0, 1) * (#frame - 1) + 1
    local i0 = math.floor(pos)
    local i1 = math.min(#frame, i0 + 1)
    local t = pos - i0
    return lerp(frame[i0], frame[i1], t)
end

-- Return the GIF-derived boundary X coordinate (0..1 from the left). Only the
-- boundary moves; neither old nor new page pixels are rescaled.
local function flipEdgeX(progress, y_norm)
    progress = clamp(progress, 0, 1)

    for i = 1, #FLIP_EDGE_TIMES - 1 do
        local t0 = FLIP_EDGE_TIMES[i]
        local t1 = FLIP_EDGE_TIMES[i + 1]
        if progress <= t1 then
            local local_t = t1 > t0 and ((progress - t0) / (t1 - t0)) or 0
            local x0 = sampleFlipEdgeState(i - 1, y_norm)
            local x1 = sampleFlipEdgeState(i, y_norm)
            return clamp(lerp(x0, x1, local_t), 0, 1)
        end
    end

    return 0
end

-- Return how much of a horizontal band has been revealed (0..1).
-- Diagonal mode bulges most around the middle. Curved-bottom variants keep the
-- top nearly straight while concentrating different amounts of lead near the
-- lower corner. page_flip uses the traced reference GIF as its moving edge.
local function shapedProgress(shape, progress, y_norm)
    if shape == "diagonal" then
        -- Bottom is ahead, top is behind. The edge remains approximately
        -- diagonal while both ends converge to a straight edge at completion.
        local envelope = 4 * progress * (1 - progress)
        return clamp(progress + 0.22 * (y_norm - 0.5) * envelope, 0, 1)
    elseif shape == "bottom_curve" then
        -- Original curved bottom flip.
        local bottom_weight = y_norm ^ 4
        local remaining_lead = 0.45 * bottom_weight * (1 - progress)
        return clamp(progress + remaining_lead, 0, 1)
    elseif shape == "bottom_curve2" then
        -- Candidate chosen in the interactive demo:
        -- clamp(progress + 0.63 * (y_norm ^ 8) * ((1-progress) ^ 1), 0, 1)
        local bottom_weight = y_norm ^ 8
        local remaining_lead = 0.63 * bottom_weight * ((1 - progress) ^ 1)
        return clamp(progress + remaining_lead, 0, 1)
    elseif shape == "bottom_curve3" then
        -- Hybrid candidate chosen in the interactive demo:
        -- startLead = 0.41 * (y_norm ^ 8) * ((1-progress) ^ 3)
        -- bulge     = 0.18 * (y_norm ^ 8) * (4*progress*(1-progress))
        local bottom_weight = y_norm ^ 8
        local start_lead = 0.41 * bottom_weight * ((1 - progress) ^ 3)
        local bulge = 0.18 * bottom_weight * (4 * progress * (1 - progress))
        return clamp(progress + start_lead + bulge, 0, 1)
    elseif shape == "page_flip" then
        -- The generic reveal renderer expects 0 = all old page and 1 = all new
        -- page. The traced GIF stores the opposite quantity: the X coordinate
        -- of the old/new boundary measured from the left.
        return clamp(1 - flipEdgeX(progress, y_norm), 0, 1)
    end
    return progress
end

-- KPW4 reveal with configurable temporal steps. Straight mode uses full-height
-- vertical strips. Shaped modes divide the page into horizontal bands in RAM,
-- but still submit only ONE panel update per temporal step: the bounding
-- rectangle containing every newly revealed band.
function StripReveal.run(old, new, direction, config)
    config = config or {}
    local ready, why = StripReveal.preflight(config)
    if not ready then error(why) end

    local sw, sh = Screen.bb:getWidth(), Screen.bb:getHeight()
    local steps = math.max(1, math.floor(tonumber(config.steps) or 6))
    local delay_ms = math.max(0, tonumber(config.delay_ms) or 40)
    local scheduler = config.scheduler == "fixed" and "fixed" or "free"
    local waveform = config.waveform or "auto"
    local shape = config.shape or "straight"
    local band_count = shape == "straight" and 1 or SHAPE_BANDS
    local band_h = math.ceil(sh / band_count)
    local previous = {}
    local last_marker
    local started = nowSeconds()

    for band = 1, band_count do previous[band] = 0 end
    Screen.bb:blitFrom(old, 0, 0, 0, 0, sw, sh)

    for i = 1, steps do
        -- Fixed mode targets absolute strip times, so drawing/submit overhead
        -- does not accumulate into progressively later frames.
        if scheduler == "fixed" and i > 1 and delay_ms > 0 then
            local deadline = started + ((i - 1) * delay_ms / 1000)
            local now = nowSeconds()
            if now < deadline then
                ffiUtil.usleep(math.floor((deadline - now) * 1000000))
            end
        end

        local progress = i / steps
        local dirty_left = sw
        local dirty_right = 0
        local changed = false

        for band = 1, band_count do
            local y = (band - 1) * band_h
            if y >= sh then break end
            local bh = math.min(band_h, sh - y)
            local y_norm = (y + bh * 0.5) / sh
            local local_progress = shapedProgress(shape, progress, y_norm)
            local dx = math.floor(sw * local_progress + 0.5)
            local prev_dx = previous[band] or 0

            -- Keep every band monotonic so a slightly noisy traced GIF edge can
            -- never move backwards and re-expose pixels from the old page.
            if dx < prev_dx then dx = prev_dx end
            if i == steps then dx = sw end

            local changed_w = dx - prev_dx
            if changed_w > 0 then
                local x
                if direction > 0 then
                    x = sw - dx
                    Screen.bb:blitFrom(new, x, y, x, y, changed_w, bh)
                else
                    x = prev_dx
                    Screen.bb:blitFrom(new, x, y, x, y, changed_w, bh)
                end
                dirty_left = math.min(dirty_left, x)
                dirty_right = math.max(dirty_right, x + changed_w)
                changed = true
            end
            previous[band] = dx
        end

        if changed and dirty_right > dirty_left then
            -- One E-Ink update per temporal step. For shaped edges this box is
            -- wider than the actually changed pixels, but avoids many small
            -- panel submissions and keeps the animation smooth on PW4.
            last_marker = submitRegion(
                waveform, dirty_left, 0, dirty_right - dirty_left, sh) or last_marker
        end

        if scheduler == "free" and i < steps then
            sleepMs(delay_ms)
        end
    end

    waitMarker(last_marker)
    Screen.bb:blitFrom(new, 0, 0, 0, 0, sw, sh)
    return {
        style = "strip",
        shape = shape,
        frames = steps,
        delay_ms = delay_ms,
        scheduler = scheduler,
        waveform = waveform,
        elapsed = nowSeconds() - started,
    }
end

return StripReveal
