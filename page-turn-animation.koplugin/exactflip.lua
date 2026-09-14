local Device = require("device")
local ffiUtil = require("ffi/util")

local Screen = Device.screen
local ExactFlip = {}

-- Exact silhouette trace from the supplied 202x270 reference GIF.
-- Duplicate source frames were merged into four 120 ms visible states.
local REF_W = 202
local REF_H = 270

local STATES = {
    { min_y = 9, max_y = 261, duration_ms = 120, data = "50,64;34,80;22,86;15,96;13,103;9,107;7,116;4,123;1,149;1,183;1,183;1,183;1,183;1,183;1,182;1,182;1,182;1,182;1,182;1,182;1,182;1,182;1,182;1,182;1,181;1,181;1,181;1,181;1,181;1,181;1,181;1,181;1,181;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,180;1,179;1,179;1,179;1,179;1,179;1,179;1,179;1,179;1,179;1,179;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,178;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,177;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,176;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,175;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,174;1,173;1,173;1,173;1,173;1,173;1,173;1,173;1,173;1,173;1,173;1,173;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,172;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,171;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,170;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,169;1,167;1,165;1,162;1,159;1,156;1,152;1,148;1,145;1,142;1,138;4,132;6,128;10,124;15,120;20,116;26,112;32,102;40,95;51,86;60,75" },
    { min_y = 2, max_y = 266, duration_ms = 120, data = "43,52;36,60;28,69;21,74;17,78;13,82;10,85;7,88;6,91;5,94;4,97;3,101;2,107;2,114;1,122;1,149;1,153;1,152;1,152;1,152;1,152;1,152;1,151;1,151;1,151;1,151;1,151;1,150;1,150;1,150;1,150;1,150;1,149;1,149;1,149;1,149;1,149;1,149;1,149;1,149;1,149;1,148;1,148;1,148;1,148;1,148;1,148;1,147;1,147;1,147;1,147;1,147;1,147;1,147;1,147;1,147;1,146;1,146;1,146;1,146;1,146;1,145;1,145;1,145;1,145;0,145;0,145;0,145;0,145;0,145;0,144;0,144;0,144;0,144;0,144;0,143;0,143;0,143;0,143;0,143;0,143;0,143;0,142;0,142;0,142;0,142;0,141;0,141;0,141;0,141;0,141;0,141;0,141;0,141;0,141;0,140;0,140;0,140;0,140;0,140;0,140;0,140;0,140;0,140;0,139;0,139;0,139;0,139;0,139;0,139;0,139;0,139;0,139;0,138;0,138;0,138;0,138;0,138;0,138;0,138;0,138;0,138;0,137;0,137;0,137;0,137;0,137;0,137;0,137;0,137;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,136;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,135;0,134;0,134;0,134;0,134;0,134;0,134;0,134;0,134;0,134;0,134;0,134;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;0,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,133;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,132;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,131;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,130;1,129;1,124;1,120;1,117;1,115;1,112;2,109;3,107;4,105;6,102;7,99;9,95;11,91;13,86;15,82;18,79;20,75;24,70;27,65;31,58" },
    { min_y = 1, max_y = 266, duration_ms = 120, data = "27,40;20,47;16,55;12,60;9,63;7,65;5,70;4,72;4,74;3,76;3,78;3,80;2,82;2,86;2,89;2,92;1,92;1,92;1,92;1,91;1,91;1,91;0,90;0,90;0,90;0,89;0,89;0,89;0,89;0,89;0,88;0,88;0,88;0,87;0,87;0,87;0,86;0,86;0,86;0,86;0,86;0,85;0,85;0,85;0,84;0,84;0,84;0,84;0,83;0,83;0,83;0,83;0,82;0,82;0,82;0,81;0,81;0,81;0,80;0,80;0,80;0,80;0,80;0,80;0,79;0,79;0,79;0,79;0,78;0,78;0,78;0,78;0,78;0,77;0,77;0,77;0,77;0,77;0,76;0,76;0,76;0,75;0,75;0,75;0,75;0,75;0,74;0,74;0,74;0,74;0,74;0,74;0,73;0,73;0,73;0,73;0,72;0,72;0,72;0,72;0,72;0,72;0,71;0,71;0,71;0,71;0,71;0,70;0,70;0,70;0,70;0,70;0,69;0,69;0,69;0,69;0,69;0,69;0,68;0,68;0,68;0,68;0,68;0,68;0,68;0,67;0,67;0,67;0,67;0,67;0,66;0,66;0,66;0,66;0,66;0,66;0,66;0,66;0,66;0,66;0,65;0,65;0,65;0,65;0,65;0,64;0,64;0,64;0,64;0,64;0,64;0,64;0,64;0,64;0,64;0,63;0,63;0,63;0,63;0,63;0,62;0,62;0,62;0,62;0,62;0,62;0,62;0,62;0,62;0,61;0,61;0,61;0,61;0,61;0,61;0,61;0,61;0,60;0,60;0,60;0,60;0,60;0,60;0,60;0,59;0,59;0,59;0,59;0,59;0,59;0,58;0,58;0,58;0,58;0,58;0,58;0,58;0,57;0,57;0,57;0,57;0,57;0,57;0,57;0,56;0,56;0,56;0,56;0,56;0,56;0,56;0,55;0,55;0,55;0,55;0,55;0,55;0,55;0,54;0,54;0,54;0,54;0,54;0,54;0,54;0,54;0,54;0,54;0,53;0,53;0,53;0,53;0,53;0,53;0,53;0,53;0,53;0,52;0,52;0,52;0,52;0,52;0,52;0,52;0,52;0,51;0,51;0,51;0,51;1,51;1,51;1,50;1,50;1,50;1,50;2,50;2,50;2,49;3,49;3,49;4,49;6,47;8,44;10,40;14,38;20,33" },
    { min_y = 0, max_y = 269, duration_ms = 120, data = "24,40;14,40;6,40;1,40;0,40;0,40;0,40;0,40;0,40;0,40;0,40;0,40;0,40;0,40;0,39;0,39;0,39;0,39;0,39;0,39;0,39;0,39;0,39;0,39;0,38;0,38;0,38;0,38;0,38;0,38;0,37;0,37;0,37;0,37;0,37;0,37;0,37;0,37;0,37;0,36;0,36;0,36;0,36;0,36;0,36;0,35;0,35;0,35;0,35;0,35;0,35;0,35;0,35;0,35;0,35;0,35;0,34;0,34;0,34;0,34;0,34;0,34;0,34;0,34;0,34;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,33;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,32;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,31;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,30;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,28;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;0,29;3,29;10,29;18,29" }
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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
        Screen:refreshUI(x, y, w, h)
    end
    if Screen.marker and Screen.marker ~= before then
        return Screen.marker
    end
end

local function decodeRows(state)
    if state.rows then return state.rows end
    local rows = {}
    for left, right in state.data:gmatch("(%d+),(%d+)") do
        rows[#rows + 1] = { tonumber(left), tonumber(right) }
    end
    state.rows = rows
    return rows
end

local function stateBounds(state, direction, sw, sh)
    local rows = decodeRows(state)
    local min_x = REF_W
    local max_x = 0

    for _, pair in ipairs(rows) do
        if pair[1] < min_x then min_x = pair[1] end
        if pair[2] > max_x then max_x = pair[2] end
    end

    local x0 = math.floor(min_x * sw / REF_W)
    local x1 = math.floor((max_x + 1) * sw / REF_W)
    local y0 = math.floor(state.min_y * sh / REF_H)
    local y1 = math.floor((state.max_y + 1) * sh / REF_H)

    x0 = clamp(x0, 0, sw)
    x1 = clamp(x1, x0, sw)
    y0 = clamp(y0, 0, sh)
    y1 = clamp(y1, y0, sh)

    if direction < 0 then
        x0, x1 = sw - x1, sw - x0
    end

    return x0, y0, x1, y1
end

local function blitState(old, new, state, direction, sw, sh)
    Screen.bb:blitFrom(new, 0, 0, 0, 0, sw, sh)

    local rows = decodeRows(state)
    for row_index, pair in ipairs(rows) do
        local ref_y = state.min_y + row_index - 1
        local y0 = math.floor(ref_y * sh / REF_H)
        local y1 = math.floor((ref_y + 1) * sh / REF_H)
        if y1 <= y0 then y1 = math.min(sh, y0 + 1) end

        if y0 < sh and y1 > y0 then
            local x0 = math.floor(pair[1] * sw / REF_W)
            local x1 = math.floor((pair[2] + 1) * sw / REF_W)
            x0 = clamp(x0, 0, sw)
            x1 = clamp(x1, x0, sw)

            if direction < 0 then
                x0, x1 = sw - x1, sw - x0
            end

            local w = x1 - x0
            if w > 0 then
                -- Same-coordinate copy: exact mask, no page compression.
                Screen.bb:blitFrom(old, x0, y0, x0, y0, w, y1 - y0)
            end
        end
    end
end

-- Create an interruptible version of the traced animation. The synchronous
-- runner below is kept for compatibility, but the page-turn hook uses these
-- two functions so KOReader can process input between visible states.
function ExactFlip.start(old, new, direction, config)
    config = config or {}
    local sw, sh = Screen.bb:getWidth(), Screen.bb:getHeight()
    return {
        style = "exact_trace",
        shape = "page_flip_exact",
        old = old,
        new = new,
        direction = direction,
        waveform = config.waveform or "auto",
        sw = sw,
        sh = sh,
        state_index = 1,
        prev_x0 = 0,
        prev_y0 = 0,
        prev_x1 = sw,
        prev_y1 = sh,
        last_marker = nil,
        started = nowSeconds(),
    }
end

function ExactFlip.step(animation)
    local sw, sh = animation.sw, animation.sh
    local state = STATES[animation.state_index]

    if state then
        blitState(
            animation.old,
            animation.new,
            state,
            animation.direction,
            sw,
            sh
        )

        local x0, y0, x1, y1 = stateBounds(
            state,
            animation.direction,
            sw,
            sh
        )
        local dirty_x0 = math.min(animation.prev_x0, x0)
        local dirty_y0 = math.min(animation.prev_y0, y0)
        local dirty_x1 = math.max(animation.prev_x1, x1)
        local dirty_y1 = math.max(animation.prev_y1, y1)

        animation.last_marker = submitRegion(
            animation.waveform,
            dirty_x0,
            dirty_y0,
            dirty_x1 - dirty_x0,
            dirty_y1 - dirty_y0
        ) or animation.last_marker

        animation.prev_x0, animation.prev_y0 = x0, y0
        animation.prev_x1, animation.prev_y1 = x1, y1
        animation.state_index = animation.state_index + 1

        return {
            done = false,
            delay = math.max(0, state.duration_ms) / 1000,
        }
    end

    -- The source GIF ends on a blank frame. Here that means only the new page.
    Screen.bb:blitFrom(animation.new, 0, 0, 0, 0, sw, sh)
    animation.last_marker = submitRegion(
        animation.waveform,
        animation.prev_x0,
        animation.prev_y0,
        animation.prev_x1 - animation.prev_x0,
        animation.prev_y1 - animation.prev_y0
    ) or animation.last_marker

    return {
        done = true,
        result = {
            style = animation.style,
            shape = animation.shape,
            frames = #STATES,
            delay_ms = 120,
            scheduler = "reference",
            waveform = animation.waveform,
            elapsed = nowSeconds() - animation.started,
        },
    }
end

function ExactFlip.run(old, new, direction, config)
    config = config or {}
    local waveform = config.waveform or "auto"
    local sw, sh = Screen.bb:getWidth(), Screen.bb:getHeight()
    local started = nowSeconds()
    local last_marker

    -- The panel initially contains the whole old page.
    local prev_x0, prev_y0, prev_x1, prev_y1 = 0, 0, sw, sh

    for _, state in ipairs(STATES) do
        blitState(old, new, state, direction, sw, sh)

        local x0, y0, x1, y1 = stateBounds(state, direction, sw, sh)
        local dirty_x0 = math.min(prev_x0, x0)
        local dirty_y0 = math.min(prev_y0, y0)
        local dirty_x1 = math.max(prev_x1, x1)
        local dirty_y1 = math.max(prev_y1, y1)

        last_marker = submitRegion(
            waveform,
            dirty_x0, dirty_y0,
            dirty_x1 - dirty_x0,
            dirty_y1 - dirty_y0
        ) or last_marker

        -- Preserve the source GIF's 120 ms visible-state cadence.
        sleepMs(state.duration_ms)

        prev_x0, prev_y0, prev_x1, prev_y1 = x0, y0, x1, y1
    end

    -- The source GIF ends on a blank frame. Here that means only the new page.
    Screen.bb:blitFrom(new, 0, 0, 0, 0, sw, sh)
    last_marker = submitRegion(
        waveform,
        prev_x0, prev_y0,
        prev_x1 - prev_x0,
        prev_y1 - prev_y0
    ) or last_marker

    waitMarker(last_marker)

    return {
        style = "exact_trace",
        shape = "page_flip_exact",
        frames = #STATES,
        delay_ms = 120,
        scheduler = "reference",
        waveform = waveform,
        elapsed = nowSeconds() - started,
    }
end

return ExactFlip
