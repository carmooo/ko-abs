local _ = require("gettext")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local abs_client = require("abs_client")

local ok, server_config = pcall(require, "config")

if not ok then
	server_config = {}
end

local KoAbs = WidgetContainer:extend({
	name = "ko-abs",
	is_doc_only = false,
})

function KoAbs:init()
	self.ui.menu:registerToMainMenu(self)
	self.libraries = {}
	self.items = {}
end

function KoAbs:addToMainMenu(menu_items)
	menu_items.ko_abs = {
		text = _("AudioBookShelf"),
		sorting_hint = "tools",
		callback = function()
			self:showBrowser()
		end,
	}
end

function KoAbs:showBrowser()
	-- TODO remove
	local config = { server_url = server_config.server_url }
	local client = abs_client:new(config)

	local token, user_id, err = client:login(server_config.username, server_config.password)
	if err then
		UIManager:show(InfoMessage:new({
			text = _("Login error: ") .. err,
		}))
		return
	end

	local libraries, err = client:getLibraries()
	if err then
		UIManager:show(InfoMessage:new({
			text = _("Error getting libraries: ") .. err,
		}))
		return
	end

	self.libraries = libraries
	self.selected_library = self.selected_library or self.libraries[1]

	self:renderBrowser(client)
end

function KoAbs:renderBrowser(client)
	local library = self.selected_library
	local items = {}

	table.insert(items, {
		text = _("Library: ") .. library.name .. " v",
		callback = function()
			self:showLibraryPicker()
		end,
	})

	local items, err = client:getLibraryItems(self.selected_library.id)
	if err then
		UIManager:show(InfoMessage:new({
			text = _("Error getting library items: ") .. err,
		}))
		return
	end

	self.items = items

	for i, book in ipairs(self.items.results or {}) do
		local selected_book = book

		table.insert(items, {
			text = _(selected_book.media.metadata.title) .. "\n" .. _(selected_book.media.metadata.authorName),
			callback = function()
				UIManager:show(InfoMessage:new({
					_(selected_book.media.metadata.title) .. "\n" .. _(selected_book.media.metadata.authorName),
				}))
			end,
		})
	end

	self.browser_menu = Menu:new({
		title = _("AudioBookShelf"),
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
