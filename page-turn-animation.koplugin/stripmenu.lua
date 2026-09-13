local Menu = {}

function Menu.augment(PageTurnAnimation, radioItem)
    local Dispatcher = require("dispatcher")
    local _ = require("gettext")

    local old_init = PageTurnAnimation.init
    function PageTurnAnimation:init()
        old_init(self)
        self.strip_waveform = G_reader_settings:readSetting("pageturnanimation_strip_waveform") or "auto"
        self.strip_shape = G_reader_settings:readSetting("pageturnanimation_strip_shape") or "straight"
        if self.strip_shape ~= "straight" and self.strip_shape ~= "diagonal"
                and self.strip_shape ~= "bottom_curve" then
            self.strip_shape = "straight"
        end
        self.page_scheduler = G_reader_settings:readSetting("pageturnanimation_page_scheduler") or "free"
        if self.page_scheduler ~= "free" and self.page_scheduler ~= "fixed" then
            self.page_scheduler = "free"
        end
        self.page_delay_ms = tonumber(G_reader_settings:readSetting("pageturnanimation_page_delay_ms")) or 40
        self.page_steps = tonumber(G_reader_settings:readSetting("pageturnanimation_page_steps")) or 6
        if self.page_steps ~= 3 and self.page_steps ~= 6 and self.page_steps ~= 12
                and self.page_steps ~= 18 and self.page_steps ~= 24 then
            self.page_steps = 6
        end
        local saved_full_refresh = G_reader_settings:readSetting("pageturnanimation_strip_full_refresh")
        self.strip_full_refresh = saved_full_refresh == true
        local saved_auto = G_reader_settings:readSetting("pageturnanimation_auto_page_turn")
        self.auto_page_turn = saved_auto == nil and true or saved_auto == true
        self:onPageTurnAnimationRegisterActions()
    end

    function PageTurnAnimation:setPageSetting(key, value)
        self[key] = value
        G_reader_settings:saveSetting("pageturnanimation_" .. key, value)
    end

    function PageTurnAnimation:setAutoPageTurn(enabled)
        self.auto_page_turn = enabled and true or false
        G_reader_settings:saveSetting("pageturnanimation_auto_page_turn", self.auto_page_turn)
    end

    function PageTurnAnimation:getPageTurnConfig()
        return {
            waveform = self.strip_waveform,
            shape = self.strip_shape,
            scheduler = self.page_scheduler,
            delay_ms = self.page_delay_ms,
            steps = self.page_steps,
            full_refresh = self.strip_full_refresh,
        }
    end

    function PageTurnAnimation:onPageTurnAnimationRegisterActions()
        Dispatcher:registerAction("pageturnanimation_animated_next", {
            category = "none",
            event = "PageTurnAnimationAnimatedNext",
            title = _("Animated page turn: next page"),
            reader = true,
        })
        Dispatcher:registerAction("pageturnanimation_animated_previous", {
            category = "none",
            event = "PageTurnAnimationAnimatedPrevious",
            title = _("Animated page turn: previous page"),
            reader = true,
        })
    end

    function PageTurnAnimation:onPageTurnAnimationAnimatedNext()
        self:turnPageForTest(1)
    end

    function PageTurnAnimation:onPageTurnAnimationAnimatedPrevious()
        self:turnPageForTest(-1)
    end

    local function settingRadio(self, text, field, value)
        return radioItem(text,
            function() return self[field] == value end,
            function() self:setPageSetting(field, value) end)
    end

    function PageTurnAnimation:pageTurnSettingsItems()
        return {
            {
                text = _("Reveal shape"),
                sub_item_table = {
                    settingRadio(self, _("Straight vertical (default)"), "strip_shape", "straight"),
                    settingRadio(self, _("Diagonal — bottom first"), "strip_shape", "diagonal"),
                    settingRadio(self, _("Curved bottom flip"), "strip_shape", "bottom_curve"),
                },
            },
            {
                text = _("Waveform"),
                sub_item_table = {
                    settingRadio(self, _("AUTO / UI (default)"), "strip_waveform", "auto"),
                    settingRadio(self, _("DU / Fast"), "strip_waveform", "du"),
                    settingRadio(self, _("A2"), "strip_waveform", "a2"),
                },
            },
            {
                text = _("Scheduling"),
                sub_item_table = {
                    settingRadio(self, _("Free-running (default)"), "page_scheduler", "free"),
                    settingRadio(self, _("Fixed interval"), "page_scheduler", "fixed"),
                },
            },
            {
                text = _("Animation steps"),
                help_text = _("More steps make each reveal strip thinner, but submit more E-Ink updates. With the same delay, more steps also increase the total animation time."),
                sub_item_table = {
                    settingRadio(self, "3", "page_steps", 3),
                    settingRadio(self, "6 (default)", "page_steps", 6),
                    settingRadio(self, "12", "page_steps", 12),
                    settingRadio(self, "18", "page_steps", 18),
                    settingRadio(self, "24", "page_steps", 24),
                },
            },
            {
                text = _("Strip delay"),
                sub_item_table = {
                    settingRadio(self, "0 ms", "page_delay_ms", 0),
                    settingRadio(self, "5 ms", "page_delay_ms", 5),
                    settingRadio(self, "10 ms", "page_delay_ms", 10),
                    settingRadio(self, "20 ms", "page_delay_ms", 20),
                    settingRadio(self, "30 ms", "page_delay_ms", 30),
                    settingRadio(self, "40 ms (default)", "page_delay_ms", 40),
                    settingRadio(self, "50 ms", "page_delay_ms", 50),
                    settingRadio(self, "60 ms", "page_delay_ms", 60),
                    settingRadio(self, "80 ms", "page_delay_ms", 80),
                    settingRadio(self, "100 ms", "page_delay_ms", 100),
                },
            },
            {
                text = _("Full clean refresh afterwards"),
                checked_func = function() return self.strip_full_refresh end,
                callback = function()
                    self:setPageSetting("strip_full_refresh", not self.strip_full_refresh)
                end,
                help_text = _("After the animation, force a full-screen refreshFull() cleanup. Useful with A2 ghosting, but slower and may visibly flash. When disabled, the normal full-screen UI settle is still used."),
            },
        }
    end

    function PageTurnAnimation:addToMainMenu(menu_items)
        local sub_items = {
            {
                text = _("Animate normal page turns"),
                checked_func = function() return self.auto_page_turn end,
                callback = function() self:setAutoPageTurn(not self.auto_page_turn) end,
                help_text = _("Animate normal one-page taps, swipes and page-turn keys with the KPW4 reveal."),
            },
        }

        for _, item in ipairs(self:pageTurnSettingsItems()) do
            sub_items[#sub_items + 1] = item
        end

        menu_items.pageturnanimation = {
            text = _("Page Turn Animation"),
            sorting_hint = "more_tools",
            sub_item_table = sub_items,
        }
    end
end

return Menu
