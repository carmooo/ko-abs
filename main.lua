local _ = require("gettext")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local abs_client = require("abs_client")

local KoAbs = WidgetContainer:extend({
	name = "myplugin",
	is_doc_only = false,
})

-- Temporary mock data.
local books = {
	["1"] = {
		{
			title = "The Left Hand of Darkness",
			author = "Ursula K. Le Guin",
		},
		{
			title = "The Dispossessed",
			author = "Ursula K. Le Guin",
		},
		{
			title = "Solaris",
			author = "Stanisław Lem",
		},
	},
	["2"] = {
		{
			title = "Watchmen",
			author = "Alan Moore",
		},
	},
	["3"] = {
		{
			title = "A Brief History of Time",
			author = "Stephen Hawking",
		},
	},
}

function KoAbs:init()
	self.ui.menu:registerToMainMenu(self)
	self.libraries = {}
end

function KoAbs:addToMainMenu(menu_items)
	menu_items.ko_abs = {
		text = _("KO ABS"),
		sorting_hint = "tools",
		callback = function()
			self:showBrowser()
		end,
	}
end

function KoAbs:showBrowser()
	-- TODO remove
	local config = {}
	local client = abs_client:new(config)
	local token, user_id, error = client:login()
	if error then
		UIManager:show(InfoMessage:new({
			text = _("Login error: ") .. error,
		}))
		return
	end
	local libraries, error = client:getLibraries()
	if error then
		UIManager:show(InfoMessage:new({
			text = _("Error getting libraries: ") .. error,
		}))
		return
	end
	self.libraries = libraries
	self.selected_library = self.selected_library or self.libraries[1]
	self:renderBrowser()
end

function KoAbs:renderBrowser()
	local library = self.selected_library
	local items = {}

	table.insert(items, {
		text = _("Library: ") .. library.name .. " v",
		callback = function()
			self:showLibraryPicker()
		end,
	})

	for i, book in ipairs(books[library.id] or {}) do
		local selected_book = book

		table.insert(items, {
			text = _(selected_book.title) .. "\n" .. _(selected_book.author),
			callback = function()
				UIManager:show(InfoMessage:new({
					_(selected_book.title) .. "\n" .. _(selected_book.author),
				}))
			end,
		})
	end

	self.browser_menu = Menu:new({
		title = _("KO ABS"),
		item_table = items,
	})

	UIManager:show(self.browser_menu)
end

function KoAbs:showLibraryPicker()
	local dialog
	local buttons = {}

	for i, library in ipairs(self.libraries) do
		local selected_library = library

		table.insert(buttons, {
			{
				text = _(selected_library.name),
				callback = function()
					UIManager.close(dialog)

					self.selected_library = selected_library

					if self.browser_menu then
						UIManager.close(self.browser_menu)
					end

					self:renderBrowser()
				end,
			},
		})
	end

	dialog = ButtonDialog:new({
		title = _("Select library"),
		buttons = buttons,
		shrink_unneeded_width = true,
	})

	UIManager:show(dialog)
end

return KoAbs
