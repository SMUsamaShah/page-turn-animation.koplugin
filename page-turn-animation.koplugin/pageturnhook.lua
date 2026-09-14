local Device = require("device")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen
local Hook = {}

-- UIManager caches the public Screen.refresh* functions at module load, while
-- those functions still dispatch to refresh*Imp dynamically. Intercept the Imp
-- methods so a plugin loaded later can replace the physical repaint reliably.
local REFRESH_IMP_METHODS = {
    "refreshFullImp",
    "refreshPartialImp",
    "refreshNoMergePartialImp",
    "refreshFlashPartialImp",
    "refreshUIImp",
    "refreshNoMergeUIImp",
    "refreshFlashUIImp",
    "refreshFastImp",
    "refreshA2Imp",
}

-- A zero-delay task would be consumed by UIManager's due-task loop without
-- polling input. One millisecond is effectively immediate on an e-reader,
-- while still giving the event loop a chance to receive another tap.
local MIN_ASYNC_DELAY = 0.001

local function freeBuffer(bb)
    if bb then pcall(function() bb:free() end) end
end

local function restoreBuffer(screen, bb)
    local w, h = screen.bb:getWidth(), screen.bb:getHeight()
    screen.bb:blitFrom(bb, 0, 0, 0, 0, w, h)
end

local function clearArm(state)
    freeBuffer(state.old_bb)
    state.old_bb = nil
    state.direction = nil
    state.armed = false
end

local function cancelAnimation(state, reason)
    local animation = state.animation
    if not animation then return end

    animation.cancelled = true
    if animation.action then
        pcall(function() UIManager:unschedule(animation.action) end)
    end
    state.animation = nil

    -- The scheduled closure may still exist in a local task frame even after
    -- unschedule. Clearing its buffers makes a stale callback harmless.
    freeBuffer(animation.old)
    freeBuffer(animation.new)
    animation.old = nil
    animation.new = nil

    if reason then
        logger.info("PageTurnAnimation: cancelled animation (" .. reason .. ")")
    end
end

local function decrementInterceptedRefresh()
    -- The refresh that started the page repaint was swallowed. Animation
    -- frames are direct Screen refreshes and do not belong to this counter.
    if UIManager.refresh_count and UIManager.refresh_count > 0 then
        UIManager.refresh_count = UIManager.refresh_count - 1
    end
end

local function settle(screen, config)
    local w, h = screen.bb:getWidth(), screen.bb:getHeight()
    if config.full_refresh and screen.refreshFull then
        -- Strong cleanup option for aggressive waveforms such as A2. This is
        -- deliberately stronger than the normal AUTO/UI settle and may flash.
        screen:refreshFull(0, 0, w, h)
    elseif screen.refreshUI then
        -- Default behavior: one full-screen UI/AUTO settle after the reveal.
        screen:refreshUI(0, 0, w, h)
    elseif screen.refreshPartial then
        screen:refreshPartial(0, 0, w, h)
    end
    if screen.refreshWaitForLast then screen:refreshWaitForLast() end
end

local function finishAnimation(state, animation, result)
    if state.animation ~= animation or animation.cancelled then return end

    state.animation = nil
    state.suppress = false
    local owner = state.owner
    local old_bb, new_bb = animation.old, animation.new
    animation.old = nil
    animation.new = nil

    -- Async frames run outside UIManager's paint pass. Re-enter the framebuffer
    -- paint bracket so devices with per-paint rotation bookkeeping stay valid.
    state.bypass = true
    local ok, why = pcall(function()
        Screen:beforePaint()
        restoreBuffer(Screen, new_bb)
        settle(Screen, animation.config or {})
        Screen:afterPaint()
    end)
    state.bypass = false

    if not ok then
        logger.warn("PageTurnAnimation: final settle failed:", why)
    end
    if owner then owner._last_page_turn_result = result end

    freeBuffer(old_bb)
    freeBuffer(new_bb)
end

local function abortAnimation(state, animation, reason)
    if state.animation ~= animation then return end

    logger.warn("PageTurnAnimation: page-turn animation failed:", reason)
    state.animation = nil
    state.suppress = false
    animation.cancelled = true
    local old_bb, new_bb = animation.old, animation.new
    animation.old = nil
    animation.new = nil

    -- The initial KOReader refresh was intercepted, so put the destination on
    -- the panel before giving control back to ordinary UI refreshes.
    if new_bb then
        state.bypass = true
        local ok, why = pcall(function()
            Screen:beforePaint()
            restoreBuffer(Screen, new_bb)
            settle(Screen, animation.config or {})
            Screen:afterPaint()
        end)
        state.bypass = false
        if not ok then
            logger.warn("PageTurnAnimation: recovery settle failed:", why)
        end
    end

    freeBuffer(old_bb)
    freeBuffer(new_bb)
end

local function scheduleAnimationStep(state, animation, delay)
    if state.animation ~= animation or animation.cancelled then return end
    delay = tonumber(delay) or 0
    if delay < MIN_ASYNC_DELAY then delay = MIN_ASYNC_DELAY end
    UIManager:scheduleIn(delay, animation.action)
end

local function runAnimationStep(state, Renderer, animation)
    if state.animation ~= animation or animation.cancelled then return end

    local ok, frame
    state.bypass = true
    local bracket_ok, bracket_error = pcall(function()
        Screen:beforePaint()
        ok, frame = pcall(Renderer.step, animation)
        Screen:afterPaint()
    end)
    state.bypass = false

    if not bracket_ok then
        abortAnimation(state, animation, bracket_error)
        return
    end
    if not ok then
        abortAnimation(state, animation, frame)
        return
    end
    if state.animation ~= animation or animation.cancelled then return end
    if type(frame) ~= "table" then
        abortAnimation(state, animation, "renderer returned no frame state")
        return
    end

    if frame.done then
        finishAnimation(state, animation, frame.result)
    else
        scheduleAnimationStep(state, animation, frame.delay)
    end
end

function Hook.augment(PageTurnAnimation, Renderer)
    local state = Screen._pageturnanimation_page_turn_hook
    if not state then
        state = {
            originals = {},
            owner = nil,
            old_bb = nil,
            direction = nil,
            armed = false,
            -- Suppresses the rest of the original repaint's refresh queue.
            -- It is cleared by afterPaint; animation callbacks use bypass.
            suppress = false,
            bypass = false,
            animation = nil,
        }
        Screen._pageturnanimation_page_turn_hook = state

        state.original_beforePaint = Screen.beforePaint
        Screen.beforePaint = function(screen, ...)
            local first_paint = not screen.painting
            local owner = state.owner
            local enabled = owner and (owner.auto_page_turn or owner._pageturnanimation_force_once)
            if first_paint and not state.bypass and enabled and owner._pageturnanimation_pending_direction then
                -- This snapshot is the currently visible composite. If a turn
                -- is already in progress, rebasing from it makes the next
                -- turn look like a fresh page layered over the partial turn.
                local snapshot = screen.bb:copy()
                cancelAnimation(state, "new page turn")
                clearArm(state)
                state.old_bb = snapshot
                state.direction = owner._pageturnanimation_pending_direction
                owner._pageturnanimation_pending_direction = nil
                owner._pageturnanimation_force_once = nil
                state.armed = true
                state.suppress = false
                logger.info("PageTurnAnimation: armed interruptible reveal, direction", state.direction)
            end
            return state.original_beforePaint(screen, ...)
        end

        state.original_afterPaint = Screen.afterPaint
        Screen.afterPaint = function(screen, ...)
            local result = state.original_afterPaint(screen, ...)
            if state.bypass then return result end
            -- A paint with no physical refresh can leave an arm behind. An
            -- animation itself owns its buffers and must survive this hook.
            if state.armed then clearArm(state) end
            state.suppress = false
            return result
        end

        local function interceptRefreshImp(name, original)
            return function(screen, ...)
                if state.bypass then return original(screen, ...) end

                -- Once the first refresh of a painted page has been consumed,
                -- discard any other refreshes in that same KOReader repaint.
                if state.suppress then return end

                if not state.armed or not state.old_bb then
                    -- A dialog or unrelated UI repaint should not be painted on
                    -- top of a moving page. Let it through, but abandon the
                    -- transition because its framebuffer is no longer ours.
                    if state.animation then
                        cancelAnimation(state, "external repaint")
                    end
                    return original(screen, ...)
                end

                local owner = state.owner
                if not owner then
                    clearArm(state)
                    return original(screen, ...)
                end

                local config = owner:getPageTurnConfig()
                local ready, why = Renderer.preflight(config)
                if not ready then
                    logger.warn("PageTurnAnimation: page-turn preflight failed:", why)
                    clearArm(state)
                    return original(screen, ...)
                end

                local old_bb = state.old_bb
                local new_bb = screen.bb:copy()
                local direction = state.direction or 1
                state.old_bb = nil
                state.direction = nil
                state.armed = false
                state.suppress = true

                logger.info("PageTurnAnimation: intercepted repaint via", name,
                    "direction", direction, "shape", config.shape,
                    "waveform", config.waveform, "scheduler", config.scheduler,
                    "delay_ms", config.delay_ms, "full_refresh", config.full_refresh)

                local ok, animation, start_error = pcall(
                    Renderer.start,
                    old_bb,
                    new_bb,
                    direction,
                    config
                )
                if not ok or not animation then
                    local why_start = not ok and animation or start_error or "renderer returned no animation"
                    logger.warn("PageTurnAnimation: could not start animation:", why_start)
                    state.suppress = false
                    freeBuffer(old_bb)
                    freeBuffer(new_bb)
                    return original(screen, ...)
                end

                animation.config = config
                state.animation = animation
                -- Keep the old composite on the RAM framebuffer until the first
                -- scheduled frame. The physical panel was already showing it.
                restoreBuffer(screen, old_bb)
                decrementInterceptedRefresh()

                animation.action = function()
                    runAnimationStep(state, Renderer, animation)
                end
                -- nextTick preserves the existing first-frame timing while
                -- ensuring the original paint pass can finish cleanly first.
                UIManager:nextTick(animation.action)
                return
            end
        end

        for _, name in ipairs(REFRESH_IMP_METHODS) do
            local original = Screen[name]
            if type(original) == "function" then
                state.originals[name] = original
                Screen[name] = interceptRefreshImp(name, original)
            end
        end
    end

    local function installNavigationHook(owner, nav)
        if not nav or nav._pageturnanimation_direction_hook then return end
        local original = nav.onGotoViewRel
        if type(original) ~= "function" then return end
        nav._pageturnanimation_direction_hook = original

        nav.onGotoViewRel = function(nav_self, diff, no_page_turn)
            local step = tonumber(diff)
            local enabled = owner.auto_page_turn or owner._pageturnanimation_force_once
            local eligible = enabled and no_page_turn ~= true and (step == 1 or step == -1)

            local before = nav_self.current_page
            if eligible then
                local direction = step
                local view = owner.ui and owner.ui.view
                if view and view.inverse_reading_order then direction = -direction end
                owner._pageturnanimation_pending_direction = direction
            end

            local result = original(nav_self, diff, no_page_turn)
            if eligible and before ~= nil and nav_self.current_page ~= nil and before == nav_self.current_page then
                owner._pageturnanimation_pending_direction = nil
                owner._pageturnanimation_force_once = nil
            end
            return result
        end
    end

    local old_init = PageTurnAnimation.init
    function PageTurnAnimation:init()
        old_init(self)
        cancelAnimation(state, "new document")
        clearArm(state)
        state.suppress = false
        state.owner = self
        installNavigationHook(self, self.ui and self.ui.paging)
        installNavigationHook(self, self.ui and self.ui.rolling)
        UIManager:nextTick(function()
            if state.owner == self and self.ui then
                installNavigationHook(self, self.ui.paging)
                installNavigationHook(self, self.ui and self.ui.rolling)
            end
        end)
    end

    local old_close = PageTurnAnimation.onCloseDocument
    function PageTurnAnimation:onCloseDocument(...)
        self._pageturnanimation_pending_direction = nil
        self._pageturnanimation_force_once = nil
        if state.owner == self then
            cancelAnimation(state, "document closed")
            state.owner = nil
            clearArm(state)
            state.suppress = false
            state.bypass = false
        end
        if old_close then return old_close(self, ...) end
    end
end

return Hook
