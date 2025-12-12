--[[--
Jellyfin UI components
@module koplugin.jellyfin.ui
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local util = require("util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local FFIUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = FFIUtil.template

local UI = {}

function UI:new(config, api)
	local o = {
		config = config,
		api = api,
		current_libraries = nil,
		current_books = nil
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function UI:configureServer()
	local input_dialog
	input_dialog = InputDialog:new {
		title = _("Enter Jellyfin Server URL"),
		input = self.config:getServerUrl(),
		input_hint = "https://jellyfin.example.com",
		buttons = {
			{
				{
					text = _("Cancel"),
					callback = function()
						UIManager:close(input_dialog)
					end,
				},
				{
					text = _("Save"),
					is_enter_default = true,
					callback = function()
						local url = input_dialog:getInputText()
						if url and url ~= "" then
							url = url:gsub("/$", "")
							self.config:setServerUrl(url)
							UIManager:show(InfoMessage:new {
								text = _("Server URL saved"),
							})
						end
						UIManager:close(input_dialog)
					end,
				},
			},
		},
	}
	UIManager:show(input_dialog)
	input_dialog:onShowKeyboard()
end

function UI:browseBooks()
	NetworkMgr:runWhenOnline(function()
		self:getBookLibraries()
	end)
end

function UI:getBookLibraries()
	UIManager:show(InfoMessage:new {
		text = _("Loading libraries..."),
		timeout = 1,
	})

	if not self.config:isLoggedIn() then
		UIManager:show(InfoMessage:new {
			text = _("Not logged in. Please login first."),
		})
		return
	end

	local success, result = self.api:getUserViews()

	if success then
		logger.info("Jellyfin UI: Response has", #result.Items, "total items")

		local book_libraries = {}

		for _, item in ipairs(result.Items) do
			logger.info("Jellyfin UI: Found library:", item.Name, "Type:", item.CollectionType or "none")
			if item.CollectionType == "books" then
				table.insert(book_libraries, item)
			end
		end

		logger.info("Jellyfin UI: Found", #book_libraries, "book libraries")

		if #book_libraries == 0 then
			UIManager:show(InfoMessage:new {
				text = _("No book libraries found"),
			})
		else
			self:showLibrariesMenu(book_libraries)
		end
	else
		logger.err("Jellyfin UI: Get libraries failed:", result)
		if result == "parse_error" then
			UIManager:show(InfoMessage:new {
				text = _("Failed to parse server response"),
			})
		else
			UIManager:show(InfoMessage:new {
				text = T(_("Failed to load libraries (code %1)"), result),
			})
		end
	end
end

function UI:showLibrariesMenu(libraries)
	logger.info("Jellyfin UI: Showing libraries menu with", #libraries, "libraries")

	self.current_libraries = libraries

	local items = {}

	for i, lib in ipairs(libraries) do
		logger.info("Jellyfin UI: Adding library to menu:", lib.Name, "ID:", lib.Id)
		table.insert(items, {
			text = lib.Name,
		})
	end

	logger.info("Jellyfin UI: Creating menu with", #items, "items")

	local menu
	menu = Menu:new {
		title = _("Select Library"),
		item_table = items,
		is_borderless = true,
		is_popout = false,
		title_bar_fm_style = true,
		onMenuChoice = function(_, choice)
			logger.info("Jellyfin UI: Menu choice:", choice.text)
			UIManager:close(menu)

			for _, lib in ipairs(self.current_libraries) do
				if lib.Name == choice.text then
					logger.info("Jellyfin UI: Library selected:", lib.Name, "ID:", lib.Id)
					self:showBooksInLibrary(lib.Id, lib.Name)
					break
				end
			end
		end,
	}

	logger.info("Jellyfin UI: Showing menu")
	UIManager:show(menu)
end

function UI:showBooksInLibrary(library_id, library_name)
	logger.info("Jellyfin UI: showBooksInLibrary called with ID:", library_id, "Name:", library_name)

	UIManager:show(InfoMessage:new {
		text = _("Loading books..."),
		timeout = 1,
	})

	local success, result = self.api:getItemsInLibrary(library_id)

	if success then
		logger.info("Jellyfin UI: Found", result.TotalRecordCount, "books")

		if result.TotalRecordCount == 0 then
			UIManager:show(InfoMessage:new {
				text = _("No books found in this library"),
			})
		else
			self:showBooksMenu(result.Items, library_name)
		end
	else
		logger.err("Jellyfin UI: Get books failed:", result)
		if result == "parse_error" then
			UIManager:show(InfoMessage:new {
				text = _("Failed to parse server response"),
			})
		else
			UIManager:show(InfoMessage:new {
				text = T(_("Failed to load books (code %1)"), result),
			})
		end
	end
end

function UI:showBooksMenu(books, library_name)
	logger.info("Jellyfin UI: Showing books menu with", #books, "books")

	self.current_books = books

	local items = {}

	for i, book in ipairs(books) do
		local read_status = book.UserData and book.UserData.Played and " ✓" or ""
		table.insert(items, {
			text = book.Name .. read_status,
		})
	end

	logger.info("Jellyfin UI: Creating books menu with", #items, "items")

	local menu
	menu = Menu:new {
		title = library_name,
		item_table = items,
		is_borderless = true,
		is_popout = false,
		title_bar_fm_style = true,
		onMenuChoice = function(_, choice)
			UIManager:close(menu)

			local book_name = choice.text:gsub(" ✓$", "")
			for _, book in ipairs(self.current_books) do
				if book.Name == book_name then
					logger.info("Jellyfin UI: Book selected:", book.Name)
					self:showBookActions(book)
					break
				end
			end
		end,
	}

	UIManager:show(menu)
end

function UI:showBookActions(book)
	logger.info("Jellyfin UI: Showing actions for book:", book.Name)

	local is_played = book.UserData and book.UserData.Played

	local button_dialog

	local buttons = {
		{
			{
				text = _("Download"),
				callback = function()
					self:downloadBook(book)
				end,
			},
		},
		{
			{
				text = is_played and _("Mark as Unread") or _("Mark as Read"),
				callback = function()
					self:toggleReadStatus(book)
				end,
			},
		},
		{
			{
				text = _("Cancel"),
				callback = function()
					UIManager:close(button_dialog)
				end,
			},
		},
	}

	button_dialog = ButtonDialog:new {
		title = book.Name,
		buttons = buttons,
	}

	UIManager:show(button_dialog)
end

function UI:downloadBook(book)
	logger.info("Jellyfin UI: Starting download for book:", book.Name, "ID:", book.Id)

	NetworkMgr:runWhenOnline(function()
		local extension = ".epub"
		if book.Path then
			extension = book.Path:match("%.([^.]+)$")
			if extension then
				extension = "." .. extension
			else
				extension = ".epub"
			end
		end

		local filename = book.Name:gsub("[^%w%s%-]", "_") .. extension
		local download_dir = DataStorage:getDataDir() .. "/books/"

		util.makePath(download_dir)

		local filepath = download_dir .. filename

		UIManager:show(InfoMessage:new {
			text = T(_("Downloading %1..."), book.Name),
			timeout = 2,
		})

		local success, error = self.api:downloadItem(book.Id, filepath)

		if success then
			UIManager:show(ConfirmBox:new {
				text = T(_("Book downloaded to:\n%1\n\nOpen now?"), filepath),
				ok_callback = function()
					local ReaderUI = require("apps/reader/readerui")
					ReaderUI:showReader(filepath)
				end,
			})
		else
			logger.err("Jellyfin UI: Download failed:", error)
			UIManager:show(InfoMessage:new {
				text = T(_("Download failed (code %1)"), error),
			})
		end
	end)
end

function UI:toggleReadStatus(book)
	logger.info("Jellyfin UI: Toggling read status for book:", book.Name)

	NetworkMgr:runWhenOnline(function()
		local is_played = book.UserData and book.UserData.Played

		UIManager:show(InfoMessage:new {
			text = _("Updating status..."),
			timeout = 1,
		})

		local success, error = self.api:setPlayedStatus(book.Id, not is_played)

		if success then
			UIManager:show(InfoMessage:new {
				text = is_played and _("Marked as unread") or _("Marked as read"),
			})
		else
			logger.err("Jellyfin UI: Update status failed:", error)
			UIManager:show(InfoMessage:new {
				text = T(_("Failed to update status (code %1)"), error),
			})
		end
	end)
end

return UI
