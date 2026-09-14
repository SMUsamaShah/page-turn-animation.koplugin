local Device = require("device")
local ffiUtil = require("ffi/util")
local RenderImage = require("ui/renderimage")

local Screen = Device.screen
local StripReveal = {}

local SHAPE_BANDS = 24
local FLIP_BANDS = 48

-- Absolute page silhouettes sampled from the approved 202x270 GIF. Each pair
-- is { left, right } in normalized full-frame coordinates for one horizontal
-- band. Unlike the curved reveal modes, this describes the remaining OLD page
-- as it narrows toward the spine; the destination page sits underneath.
local FLIP_KEYFRAMES = {
    {
        {0.1758, 0.3814}, {0.0315, 0.7027}, {0.0050, 0.9055}, {0.0050, 0.8993},
        {0.0050, 0.8955}, {0.0050, 0.8905}, {0.0050, 0.8856}, {0.0050, 0.8831},
        {0.0050, 0.8806}, {0.0050, 0.8773}, {0.0050, 0.8748}, {0.0050, 0.8706},
        {0.0050, 0.8665}, {0.0050, 0.8624}, {0.0050, 0.8574}, {0.0050, 0.8557},
        {0.0050, 0.8507}, {0.0050, 0.8483}, {0.0050, 0.8458}, {0.0050, 0.8445},
        {0.0050, 0.8408}, {0.0050, 0.8188}, {0.0489, 0.6464}, {0.2276, 0.4453},
    },
    {
        {0.0925, 0.3846}, {0.0095, 0.6405}, {0.0050, 0.7500}, {0.0050, 0.7409},
        {0.0050, 0.7330}, {0.0046, 0.7251}, {0.0000, 0.7177}, {0.0000, 0.7081},
        {0.0000, 0.6994}, {0.0000, 0.6936}, {0.0000, 0.6878}, {0.0000, 0.6808},
        {0.0000, 0.6766}, {0.0000, 0.6725}, {0.0000, 0.6683}, {0.0000, 0.6633},
        {0.0029, 0.6617}, {0.0050, 0.6600}, {0.0050, 0.6567}, {0.0050, 0.6530},
        {0.0050, 0.6509}, {0.0050, 0.6464}, {0.0153, 0.5531}, {0.0929, 0.3875},
    },
    {
        {0.0498, 0.3166}, {0.0083, 0.4378}, {0.0004, 0.4436}, {0.0000, 0.4287},
        {0.0000, 0.4125}, {0.0000, 0.3980}, {0.0000, 0.3868}, {0.0000, 0.3740},
        {0.0000, 0.3624}, {0.0000, 0.3520}, {0.0000, 0.3416}, {0.0000, 0.3329},
        {0.0000, 0.3255}, {0.0000, 0.3176}, {0.0000, 0.3101}, {0.0000, 0.3035},
        {0.0000, 0.2952}, {0.0000, 0.2865}, {0.0000, 0.2790}, {0.0000, 0.2711},
        {0.0000, 0.2653}, {0.0000, 0.2587}, {0.0050, 0.2504}, {0.0387, 0.2200},
    },
    {
        {0.0187, 0.1990}, {0.0000, 0.1953}, {0.0000, 0.1882}, {0.0000, 0.1816},
        {0.0000, 0.1737}, {0.0000, 0.1679}, {0.0000, 0.1642}, {0.0000, 0.1596},
        {0.0000, 0.1567}, {0.0000, 0.1542}, {0.0000, 0.1542}, {0.0000, 0.1501},
        {0.0000, 0.1493}, {0.0000, 0.1493}, {0.0000, 0.1451}, {0.0000, 0.1443},
        {0.0000, 0.1443}, {0.0000, 0.1410}, {0.0000, 0.1393}, {0.0000, 0.1393},
        {0.0000, 0.1405}, {0.0000, 0.1443}, {0.0000, 0.1443}, {0.0129, 0.1443},
    },
}

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

-- Sample one of the four traced GIF silhouettes at an arbitrary vertical
-- position. The fifth/final keyframe is synthesized as a zero-width edge at
-- the left side of the fourth silhouette, matching the GIF's blank final frame.
local function sampleFlipKeyframe(index, y_norm)
    local source_index = math.min(index, #FLIP_KEYFRAMES)
    local frame = FLIP_KEYFRAMES[source_index]
    local pos = clamp(y_norm, 0, 1) * (#frame - 1) + 1
    local i0 = math.floor(pos)
    local i1 = math.min(#frame, i0 + 1)
    local t = pos - i0
    local a = frame[i0]
    local b = frame[i1]
    local left = lerp(a[1], b[1], t)
    local right = lerp(a[2], b[2], t)

    if index > #FLIP_KEYFRAMES then
        return left, left
    end
    return left, right
end

local function flipGeometry(progress, y_norm)
    local keyframe_count = #FLIP_KEYFRAMES + 1 -- plus the collapsed/blank frame
    local pos = clamp(progress, 0, 1) * (keyframe_count - 1) + 1
    local i0 = math.floor(pos)
    local i1 = math.min(keyframe_count, i0 + 1)
    local t = pos - i0
    local l0, r0 = sampleFlipKeyframe(i0, y_norm)
    local l1, r1 = sampleFlipKeyframe(i1, y_norm)
    return lerp(l0, l1, t), lerp(r0, r1, t)
end

-- GIF-derived page flip. The new page is placed underneath. The old page is
-- horizontally compressed as the sheet turns edge-on, then clipped into the
-- traced curved silhouette with horizontal bands. This is deliberately more
-- expensive than the strip reveals: each temporal frame scales the old page in
-- RAM, but still submits only one E-Ink update.
local function runPageFlip(old, new, direction, config)
    local sw, sh = Screen.bb:getWidth(), Screen.bb:getHeight()
    local steps = math.max(1, math.floor(tonumber(config.steps) or 6))
    local delay_ms = math.max(0, tonumber(config.delay_ms) or 40)
    local scheduler = config.scheduler == "fixed" and "fixed" or "free"
    local waveform = config.waveform or "auto"
    local band_h = math.ceil(sh / FLIP_BANDS)
    local last_marker
    local previous_left
    local previous_right
    local started = nowSeconds()

    for i = 1, steps do
        if scheduler == "fixed" and i > 1 and delay_ms > 0 then
            local deadline = started + ((i - 1) * delay_ms / 1000)
            local now = nowSeconds()
            if now < deadline then
                ffiUtil.usleep(math.floor((deadline - now) * 1000000))
            end
        end

        local progress = steps == 1 and 1 or ((i - 1) / (steps - 1))
        local geometry = {}
        local max_right_norm = 0
        local current_left = sw
        local current_right = 0

        for band = 1, FLIP_BANDS do
            local y = (band - 1) * band_h
            if y >= sh then break end
            local bh = math.min(band_h, sh - y)
            local y_norm = (y + bh * 0.5) / sh
            local left_norm, right_norm = flipGeometry(progress, y_norm)
            left_norm = clamp(left_norm, 0, 1)
            right_norm = clamp(right_norm, left_norm, 1)
            geometry[band] = { y = y, h = bh, left = left_norm, right = right_norm }

            if right_norm - left_norm > 0.0001 then
                max_right_norm = math.max(max_right_norm, right_norm)
                local x0 = math.floor(left_norm * sw + 0.5)
                local x1 = math.floor(right_norm * sw + 0.5)
                if direction > 0 then
                    current_left = math.min(current_left, x0)
                    current_right = math.max(current_right, x1)
                else
                    current_left = math.min(current_left, sw - x1)
                    current_right = math.max(current_right, sw - x0)
                end
            end
        end

        -- Compose the complete frame in RAM: clean destination underneath,
        -- compressed old page on top within the GIF silhouette.
        Screen.bb:blitFrom(new, 0, 0, 0, 0, sw, sh)

        if max_right_norm > 0 then
            local scaled_w = clamp(math.floor(max_right_norm * sw + 0.5), 1, sw)
            local scaled_old = RenderImage:scaleBlitBuffer(old, scaled_w, sh, false)

            for band = 1, #geometry do
                local g = geometry[band]
                local x0 = clamp(math.floor(g.left * sw + 0.5), 0, scaled_w)
                local x1 = clamp(math.floor(g.right * sw + 0.5), 0, scaled_w)
                local bw = x1 - x0
                if bw > 0 then
                    if direction > 0 then
                        Screen.bb:blitFrom(scaled_old, x0, g.y, x0, g.y, bw, g.h)
                    else
                        local dest_x = sw - x1
                        local src_x = scaled_w - x1
                        Screen.bb:blitFrom(scaled_old, dest_x, g.y, src_x, g.y, bw, g.h)
                    end
                end
            end

            if scaled_old ~= old then
                pcall(function() scaled_old:free() end)
            end
        end

        -- The old sheet shrinks each frame. Refresh the union of its previous
        -- and current bounds so the vacated area is replaced by the new page.
        local dirty_left = math.min(previous_left or sw, current_left)
        local dirty_right = math.max(previous_right or 0, current_right)
        if dirty_right > dirty_left then
            last_marker = submitRegion(
                waveform, dirty_left, 0, dirty_right - dirty_left, sh) or last_marker
        end

        if current_right > current_left then
            previous_left = current_left
            previous_right = current_right
        else
            previous_left = nil
            previous_right = nil
        end

        if scheduler == "free" and i < steps then
            sleepMs(delay_ms)
        end
    end

    waitMarker(last_marker)
    Screen.bb:blitFrom(new, 0, 0, 0, 0, sw, sh)
    return {
        style = "page_flip",
        shape = "page_flip",
        frames = steps,
        delay_ms = delay_ms,
        scheduler = scheduler,
        waveform = waveform,
        elapsed = nowSeconds() - started,
    }
end

-- Return how much of a horizontal band has been revealed (0..1).
-- Diagonal mode bulges most around the middle. Curved-bottom variants keep the
-- top nearly straight while concentrating different amounts of lead near the
-- lower corner.
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

    local shape = config.shape or "straight"
    if shape == "page_flip" then
        return runPageFlip(old, new, direction, config)
    end

    local sw, sh = Screen.bb:getWidth(), Screen.bb:getHeight()
    local steps = math.max(1, math.floor(tonumber(config.steps) or 6))
    local delay_ms = math.max(0, tonumber(config.delay_ms) or 40)
    local scheduler = config.scheduler == "fixed" and "fixed" or "free"
    local waveform = config.waveform or "auto"
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

            -- The formulas above are monotonic, but keep this guard so a future
            -- shape can never try to "unreveal" pixels and create ghost trails.
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
