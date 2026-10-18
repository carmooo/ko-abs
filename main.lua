local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local KoAbs = WidgetContainer:extend({
	name = "myplugin",
	is_doc_only = false,
})

function KoAbs:init()
	self.ui.menu:registerToMainMenu(self)
end

function KoAbs:addToMainMenu(menu_items)
	menu_items.ko_abs = {
		text = _("KO ABS"),
		sorting_hitn = "more_tools",
		callback = function()
			UIManager:show(InfoMessage:new({
				text = "Hello, World!",
			}))
		end,
	}
end

return KoAbs
