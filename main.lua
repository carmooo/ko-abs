local _ = require("gettext")
local ABSClient = require("abs_client")
local Archiver = require("ffi/archiver")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")

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
end

function KoAbs:addToMainMenu(menu_items)
	menu_items.ko_abs = {
		text = "AudioBookShelf",
		sorting_hint = "tools",
		callback = function()
			self:showBrowser()
		end,
	}
end

function KoAbs:showBrowser()
	local config = { server_url = server_config.server_url }
	local client = ABSClient:new(config)
	self.client = client

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

	if not libraries or #libraries < 1 then
		UIManager:show(InfoMessage:new({
			text = _("No libraries found."),
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

	local books, err = self.client:getLibraryItems(self.selected_library.id)
	if err then
		UIManager:show(InfoMessage:new({
			text = _("Error getting library items: ") .. err,
		}))
		return
	end

	for i, book in ipairs(books.results or {}) do
		local metadata = book.media and book.media.metadata or {}
		local title = metadata.title or _("Untitled")
		local author = metadata.authorName or _("Unknown author")

		table.insert(items, {
			text = title .. "\n" .. author,
			callback = function()
				self:showBookDetails(book)
			end,
		})
	end

	self.browser_menu = Menu:new({
		title = "AudioBookShelf",
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
				text = selected_library.name,
				callback = function()
					UIManager:close(dialog)

					self.selected_library = selected_library

					if self.browser_menu then
						UIManager:close(self.browser_menu)
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

function KoAbs:showBookDetails(book)
	local metadata = book.media and book.media.metadata or {}
	local title = metadata.title or _("Untitled")
	local author = metadata.authorName or _("Unknown author")

	local dialog
	dialog = ButtonDialog:new({
		title = title,
		buttons = {
			{
				{
					text = _("Download"),
					callback = function()
						UIManager:close(dialog)
						self:downloadBook(book)
					end,
				},
			},
			{
				{
					text = _("Cancel"),
					callback = function()
						UIManager:close(dialog)
					end,
				},
			},
		},
	})

	UIManager:show(dialog)
end

function KoAbs:downloadBook(book)
	local metadata = book.media and book.media.metadata or {}
	local base_dir = DataStorage:getDataDir() .. "/audiobookshelf/downloads"
	local author = util.getSafeFilename(metadata.authorName or _("Unknown author"), base_dir)
	local dest_dir = base_dir .. "/" .. author
	local id = book.id
	local path, err = self.client:downloadItem(id, dest_dir)
	if err then
		UIManager:show(InfoMessage:new({ text = _("Error downloading item.") }))
		return
	end

	-- If it is not a zip we are done
	if util.getFileNameSuffix(path):lower() ~= "zip" then
		UIManager:show(InfoMessage:new({ text = _("Item saved.") }))
		return
	end
	-- if it is a zip we unzip into a folder with the same name
	local dir, filename = util.splitFilePathName(path)
	local extract_dir = dir .. util.splitFileNameSuffix(filename)
	local archiver = Archiver.Reader:new()
	if not archiver:open(path) then
		logger.error("ko-abs: failed to open zip archive.", archiver.err)
		archiver:close()
		util.removeFile(path)
		UIManager:show(InfoMessage:new({ text = _("Error downloading item.") }))
		return
	end
	for entry in archiver:iterate() do
		if entry.mode == "file" then
			local target = extract_dir .. "/" .. entry.path
			util.makePath((util.splitFilePathName(target)))
			if not archiver:extractToPath(entry.path, target) then
				logger.error("ko-abs: failed to extract entry.", archiver.err)
				archiver:close()
				local purged, purge_err = ffiUtil.purgeDir(extract_dir)
				if not purged then
					logger.warn("ko-abs: could not purge", extract_dir, purge_err)
				end
				util.removeFile(path)
				UIManager:show(InfoMessage:new({ text = _("Error downloading item.") }))
				return
			end
		end
	end
	archiver:close()
	-- we delete the zip after successful extraction
	util.removeFile(path)
	UIManager:show(InfoMessage:new({ text = _("Item saved.") }))
end

return KoAbs
