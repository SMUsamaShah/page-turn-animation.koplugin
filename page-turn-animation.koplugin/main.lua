local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"

local PageTurnAnimation = WidgetContainer:extend{
    name = "pageturnanimation",
    is_doc_only = true,
}

function PageTurnAnimation:init()
    self.ui.menu:registerToMainMenu(self)
end

function PageTurnAnimation:turnPageForTest(direction)
    UIManager:nextTick(function()
        if self.ui then
            self._pageturnanimation_force_once = true
            self.ui:handleEvent(Event:new("GotoViewRel", direction))
        end
    end)
end

local function radioItem(text, checked, callback)
    return {
        text = text,
        radio = true,
        checked_func = checked,
        callback = callback,
    }
end

local StripReveal = dofile(plugin_dir .. "stripreveal.lua")
dofile(plugin_dir .. "stripmenu.lua").augment(PageTurnAnimation, radioItem)
dofile(plugin_dir .. "pageturnhook.lua").augment(PageTurnAnimation, StripReveal)

local updater = dofile(plugin_dir .. "pluginupdater.lua").new{
    repository = "SMUsamaShah/page-turn-animation.koplugin",
    branch = "main",
    folder = "page-turn-animation.koplugin",
}

local old_add = PageTurnAnimation.addToMainMenu
function PageTurnAnimation:addToMainMenu(menu_items)
    old_add(self, menu_items)
    local items = menu_items.pageturnanimation and menu_items.pageturnanimation.sub_item_table
    if items then items[#items + 1] = updater:menuItem() end
end

return PageTurnAnimation
