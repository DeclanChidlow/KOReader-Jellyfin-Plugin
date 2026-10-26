local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local PathChooser = require("ui/widget/pathchooser")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local FFIUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local Screen = Device.screen

local SORT_ORDER = { "title", "author", "series", "year" }
local SORT_LABELS = {
	title = _("Title"),
	author = _("Author"),
	series = _("Series"),
	year = _("Year"),
}

local FILTER_ORDER = { "all", "unread", "reading", "read" }
local FILTER_LABELS = {
	all = _("All books"),
	unread = _("Unread"),
	reading = _("In progress"),
	read = _("Read"),
}

local function bookAuthor(book)
	if not book.People then
		return nil
	end

	local names = {}
	for _, person in ipairs(book.People) do
		if person.Type == "Author" and person.Name and person.Name ~= "" then
			table.insert(names, person.Name)
		end
	end

	if #names > 0 then
		return table.concat(names, ", ")
	end
	return nil
end

local function bookProgressPercent(book)
	local ticks = book.UserData and book.UserData.PlaybackPositionTicks
	if ticks and ticks > 0 then
		return math.min(100, math.floor(ticks / 100000))
	end
	return nil
end

local function bookSortTitle(book)
	if book.SortName and book.SortName ~= "" then
		return book.SortName:lower()
	end
	return (book.Name or ""):lower()
end

local function sortBooks(books, sort_key, sort_order)
	local sorted = {}
	for _, book in ipairs(books) do
		table.insert(sorted, book)
	end

	local comparators = {
		title = function(a, b)
			return bookSortTitle(a) < bookSortTitle(b)
		end,
		author = function(a, b)
			return (bookAuthor(a) or "\255"):lower() < (bookAuthor(b) or "\255"):lower()
		end,
		series = function(a, b)
			local ia = math.floor(tonumber(a.IndexNumber) or 0)
			local ib = math.floor(tonumber(b.IndexNumber) or 0)
			local sa = (a.SeriesName or "\255") .. string.format("%09d", ia)
			local sb = (b.SeriesName or "\255") .. string.format("%09d", ib)
			return sa:lower() < sb:lower()
		end,
		year = function(a, b)
			return (a.ProductionYear or 0) < (b.ProductionYear or 0)
		end,
	}

	table.sort(sorted, comparators[sort_key] or comparators.title)

	if sort_order == "desc" then
		local n = #sorted
		for i = 1, math.floor(n / 2) do
			sorted[i], sorted[n + 1 - i] = sorted[n + 1 - i], sorted[i]
		end
	end

	return sorted
end

local function filterBooks(books, filter_key)
	local result = {}
	for _, book in ipairs(books) do
		local played = book.UserData and book.UserData.Played
		local percent = bookProgressPercent(book)

		local match
		if filter_key == "unread" then
			match = not played and not (percent and percent > 0)
		elseif filter_key == "reading" then
			match = not played and percent and percent > 0
		elseif filter_key == "read" then
			match = played
		else
			match = true
		end

		if match then
			table.insert(result, book)
		end
	end
	return result
end

local function bookItemText(book)
	local text = book.Name

	if book.UserData and book.UserData.Played then
		text = text .. "  ✓"
	end

	return text
end

local function bookItemMandatory(book)
	local parts = {}

	local author = bookAuthor(book)
	if author then
		table.insert(parts, author)
	end

	if book.ProductionYear then
		table.insert(parts, tostring(book.ProductionYear))
	end

	if #parts > 0 then
		return table.concat(parts, " · ")
	end
	return nil
end

local function bookInfoText(book)
	local lines = {}

	local author = bookAuthor(book)
	if author then
		table.insert(lines, T(_("By %1"), author))
	end

	if book.SeriesName and book.SeriesName ~= "" then
		if book.IndexNumber then
			table.insert(lines, T(_("Book %1 in %2"), book.IndexNumber, book.SeriesName))
		else
			table.insert(lines, book.SeriesName)
		end
	end

	local details = {}
	if book.ProductionYear then
		table.insert(details, tostring(book.ProductionYear))
	end
	if book.Genres and #book.Genres > 0 then
		table.insert(details, table.concat(book.Genres, ", "))
	end
	if #details > 0 then
		table.insert(lines, table.concat(details, " · "))
	end

	if book.CommunityRating and book.CommunityRating > 0 then
		table.insert(lines, T(_("Rating: %1/10"), string.format("%.1f", book.CommunityRating)))
	end

	if book.UserData and book.UserData.Played then
		table.insert(lines, _("Read"))
	else
		local percent = bookProgressPercent(book)
		if percent and percent > 0 then
			table.insert(lines, T(_("%1% read"), percent))
		else
			table.insert(lines, _("Unread"))
		end
	end

	return table.concat(lines, "\n")
end

local function bookOverviewText(book)
	if not book.Overview or book.Overview == "" then
		return nil
	end

	local overview = book.Overview
		:gsub("<br%s*/?>", "\n")
		:gsub("<[^>]+>", "")
		:gsub("&nbsp;", " ")
		:gsub("&amp;", "&")
		:gsub("&quot;", '"')
		:gsub("&#39;", "'")
		:gsub("\n\n\n+", "\n\n")
		:gsub("^%s+", "")
		:gsub("%s+$", "")

	if overview == "" then
		return nil
	end
	return overview
end

local BookActionsDialog = InputContainer:extend {}

function BookActionsDialog:init()
	self.ges_events = {
		TapClose = {
			GestureRange:new {
				ges = "tap",
				range = Geom:new {
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				},
			},
		},
	}

	local content_width = self.width - 2 * Size.padding.large

	local content = VerticalGroup:new {
		align = "center",
	}

	if self.cover_path then
		table.insert(content, FrameContainer:new {
			bordersize = Size.border.default,
			background = Blitbuffer.COLOR_WHITE,
			padding = Size.padding.tiny,
			ImageWidget:new {
				file = self.cover_path,
				scale_factor = 0,
				width = self.cover_width,
				height = self.cover_height,
				alpha = true,
			},
		})
		table.insert(content, VerticalSpan:new { width = Size.span.vertical_default })
	end

	table.insert(content, TextBoxWidget:new {
		text = self.book_name,
		face = Font:getFace("cfont", 24),
		bold = true,
		alignment = "center",
		width = content_width,
	})

	if self.info_text and self.info_text ~= "" then
		table.insert(content, TextBoxWidget:new {
			text = self.info_text,
			face = Font:getFace("cfont", 18),
			alignment = "center",
			width = content_width,
		})
	end

	table.insert(content, VerticalSpan:new { width = Size.span.vertical_default })

	table.insert(content, ButtonTable:new {
		buttons = self.buttons,
		width = content_width,
		show_parent = self,
	})

	self.frame = FrameContainer:new {
		background = Blitbuffer.COLOR_WHITE,
		bordersize = Size.border.default,
		radius = Size.radius.window,
		padding = Size.padding.large,
		content,
	}

	self[1] = CenterContainer:new {
		dimen = Screen:getSize(),
		self.frame,
	}
end

function BookActionsDialog:onShow()
	UIManager:setDirty(self, function()
		return "full", Geom:new {
			x = 0, y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight(),
		}, true
	end)
	return true
end

function BookActionsDialog:onCloseWidget()
	UIManager:setDirty(nil, function()
		return "ui", Geom:new {
			x = 0, y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight(),
		}
	end)
end

function BookActionsDialog:onTapClose(arg, ges)
	if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
		UIManager:close(self)
		return true
	end
end

local UI = {}

function UI:new(config, api)
	local o = {
		config = config,
		api = api,
		current_libraries = nil,
		current_books = nil,
		current_library_name = nil,
		books_menu = nil,
		books_item_table = nil,
		options_menu = nil,
		options_item_table = nil,
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

function UI:configureDownloadDir()
	local current_dir = self.config:getDownloadDir()

	local dialog

	local function saveDir(dir)
		self.config:setDownloadDir(dir)
		UIManager:show(InfoMessage:new {
			text = T(_("Downloads will be saved to:\n%1"), self.config:getDownloadDir()),
		})
	end

	local buttons = {
		{
			{
				text = _("Choose folder"),
				callback = function()
					UIManager:close(dialog)
					UIManager:show(PathChooser:new {
						title = true,
						select_directory = true,
						select_file = false,
						path = current_dir,
						onConfirm = function(new_dir)
							if new_dir and new_dir ~= "" then
								saveDir(new_dir)
							end
						end,
					})
				end,
			},
		},
		{
			{
				text = _("Reset to default"),
				callback = function()
					UIManager:close(dialog)
					self.config:resetDownloadDir()
					UIManager:show(InfoMessage:new {
						text = T(_("Downloads will be saved to:\n%1"), self.config:getDownloadDir()),
					})
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
	}

	dialog = ButtonDialog:new {
		title = T(_("Download folder:\n%1"), current_dir),
		buttons = buttons,
	}

	UIManager:show(dialog)
end

function UI:handleApiError(error_code, default_msg)
	if error_code == 401 then
		logger.info("Jellyfin: Encountered 401 Unauthorised, clearing auth.")
		self.config:clearAuth()
		UIManager:show(ConfirmBox:new {
			text = _("Your session is invalid or has expired.\n\nPlease log in again from the Jellyfin plugin's menu."),
		})
	elseif error_code == "parse_error" then
		UIManager:show(InfoMessage:new {
			text = _("Failed to parse server response."),
		})
	elseif error_code then
		UIManager:show(InfoMessage:new {
			text = T(_("%1 (code %2)"), default_msg, error_code),
		})
	else
		UIManager:show(InfoMessage:new {
			text = default_msg,
		})
	end
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
		logger.info("Jellyfin: Response has", #result.Items, "total items")

		local book_libraries = {}

		for _, item in ipairs(result.Items) do
			logger.info("Jellyfin: Found library:", item.Name, "Type:", item.CollectionType or "none")
			if item.CollectionType == "books" then
				table.insert(book_libraries, item)
			end
		end

		logger.info("Jellyfin: Found", #book_libraries, "book libraries")

		if #book_libraries == 0 then
			UIManager:show(InfoMessage:new {
				text = _("No book libraries found"),
			})
		else
			self:showLibrariesMenu(book_libraries)
		end
	else
		logger.err("Jellyfin: Get libraries failed:", result)
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
	logger.info("Jellyfin: Showing libraries menu with", #libraries, "libraries")

	self.current_libraries = libraries

	local items = {}

	for i, lib in ipairs(libraries) do
		logger.info("Jellyfin: Adding library to menu:", lib.Name, "ID:", lib.Id)
		table.insert(items, {
			text = lib.Name,
		})
	end

	logger.info("Jellyfin: Creating menu with", #items, "items")

	local menu
	menu = Menu:new {
		title = _("Select Library"),
		item_table = items,
		is_borderless = true,
		is_popout = false,
		title_bar_fm_style = true,
		onMenuChoice = function(_, choice)
			logger.info("Jellyfin: Menu choice:", choice.text)
			UIManager:close(menu)

			for _, lib in ipairs(self.current_libraries) do
				if lib.Name == choice.text then
					logger.info("Jellyfin: Library selected:", lib.Name, "ID:", lib.Id)
					self:showBooksInLibrary(lib.Id, lib.Name)
					break
				end
			end
		end,
	}

	logger.info("Jellyfin: Showing menu")
	UIManager:show(menu)
end

function UI:showBooksInLibrary(library_id, library_name)
	logger.info("Jellyfin: showBooksInLibrary called with ID:", library_id, "Name:", library_name)

	UIManager:show(InfoMessage:new {
		text = _("Loading books..."),
		timeout = 1,
	})

	local success, result = self.api:getItemsInLibrary(library_id)

	if success then
		logger.info("Jellyfin: Found", result.TotalRecordCount, "books")

		if result.TotalRecordCount == 0 then
			UIManager:show(InfoMessage:new {
				text = _("No books found in this library"),
			})
		else
			self:showBooksMenu(result.Items, library_name)
		end
	else
		logger.err("Jellyfin: Get books failed:", result)
		self:handleApiError(result, _("Failed to load books"))
	end
end

local function replaceTableContents(target, source)
	for i = #target, 1, -1 do
		target[i] = nil
	end
	for i, item in ipairs(source) do
		target[i] = item
	end
end

function UI:bookOptionsSummary()
	local order_arrow = self.config:getBookSortOrder() == "desc" and " ↓" or " ↑"
	local sort_label = (SORT_LABELS[self.config:getBookSort()] or SORT_LABELS.title) .. order_arrow
	local filter_label = FILTER_LABELS[self.config:getBookFilter()] or FILTER_LABELS.all
	return sort_label .. " · " .. filter_label
end

function UI:updateBooksMenuSubtitle()
	if not self.books_menu or not self.books_menu.title_bar then
		return
	end
	self.books_menu.title_bar:setSubTitle(self:bookOptionsSummary())
end

function UI:showBooksMenu(books, library_name)
	self.current_books = books
	self.current_library_name = library_name

	local menu
	menu = Menu:new {
		title = library_name,
		subtitle = self:bookOptionsSummary(),
		title_bar_left_icon = "appbar.tools",
		item_table = self:buildBookMenuItemTable(),
		is_borderless = true,
		is_popout = false,
		title_bar_fm_style = true,
	}
	self.books_item_table = menu.item_table

	menu.onLeftButtonTap = function()
		self:showBookOptionsMenu()
	end

	local original_on_close_widget = menu.onCloseWidget
	menu.onCloseWidget = function(menu_self)
		self.books_menu = nil
		if original_on_close_widget then
			original_on_close_widget(menu_self)
		end
	end

	self.books_menu = menu
	UIManager:show(menu)
end

function UI:showBookOptionsMenu()
	local menu
	menu = Menu:new {
		title = _("Sort & filter"),
		item_table = self:buildBookOptionsMenuItemTable(),
		is_borderless = true,
		is_popout = false,
		title_bar_fm_style = true,
	}
	self.options_item_table = menu.item_table

	local original_on_close_widget = menu.onCloseWidget
	menu.onCloseWidget = function(menu_self)
		self.options_menu = nil
		self.options_item_table = nil
		if original_on_close_widget then
			original_on_close_widget(menu_self)
		end
	end

	self.options_menu = menu
	UIManager:show(menu)
end

function UI:buildBookOptionsMenuItemTable()
	local items = {}

	local sort_items = {}
	for _, key in ipairs(SORT_ORDER) do
		table.insert(sort_items, {
			text = SORT_LABELS[key],
			mandatory_func = function()
				return self.config:getBookSort() == key and "✓" or nil
			end,
			callback = function()
				self.config:setBookSort(key)
				self:onBooksMenuOptionsChanged()
				self:refreshOptionsMenu()
			end,
		})
	end
	local order_arrow = self.config:getBookSortOrder() == "desc" and " ↓" or " ↑"
	table.insert(items, {
		text = _("Sort by"),
		mandatory = (SORT_LABELS[self.config:getBookSort()] or SORT_LABELS.title) .. order_arrow,
		sub_item_table = sort_items,
	})

	local order_items = {
		{
			key = "asc",
			text = _("Ascending"),
		},
		{
			key = "desc",
			text = _("Descending"),
		},
	}
	for _, order in ipairs(order_items) do
		order.mandatory_func = function()
			return self.config:getBookSortOrder() == order.key and "✓" or nil
		end
		order.callback = function()
			self.config:setBookSortOrder(order.key)
			self:onBooksMenuOptionsChanged()
			self:refreshOptionsMenu()
		end
	end
	table.insert(items, {
		text = _("Order"),
		mandatory = self.config:getBookSortOrder() == "desc" and _("Descending") or _("Ascending"),
		sub_item_table = order_items,
	})

	local filter_items = {}
	for _, key in ipairs(FILTER_ORDER) do
		table.insert(filter_items, {
			text = FILTER_LABELS[key],
			mandatory_func = function()
				return self.config:getBookFilter() == key and "✓" or nil
			end,
			callback = function()
				self.config:setBookFilter(key)
				self:onBooksMenuOptionsChanged()
				self:refreshOptionsMenu()
			end,
		})
	end
	table.insert(items, {
		text = _("Filter"),
		mandatory = FILTER_LABELS[self.config:getBookFilter()] or FILTER_LABELS.all,
		sub_item_table = filter_items,
	})

	return items
end

function UI:refreshOptionsMenu()
	if not self.options_menu or not self.options_item_table then
		return
	end
	replaceTableContents(self.options_item_table, self:buildBookOptionsMenuItemTable())
	self.options_menu:updateItems()
end

function UI:buildBookMenuItemTable()
	local visible_books = sortBooks(
		filterBooks(self.current_books, self.config:getBookFilter()),
		self.config:getBookSort(),
		self.config:getBookSortOrder()
	)

	local items = {}

	for _, book in ipairs(visible_books) do
		table.insert(items, {
			text = bookItemText(book),
			mandatory = bookItemMandatory(book),
			mandatory_dim = true,
			callback = function()
				self:showBookActions(book)
			end,
		})
	end

	if #visible_books == 0 then
		table.insert(items, {
			text = _("No books match the current filter"),
			dim = true,
		})
	end

	return items
end

function UI:rebuildBooksMenuItems()
	if not self.books_item_table then
		return
	end
	replaceTableContents(self.books_item_table, self:buildBookMenuItemTable())
end

function UI:onBooksMenuOptionsChanged()
	if not self.books_menu then
		return
	end
	self.books_menu.page = 1
	self.books_menu.itemnumber = nil
	self:rebuildBooksMenuItems()
	self.books_menu:updateItems()
	self:updateBooksMenuSubtitle()
end

function UI:refreshBooksMenu()
	if not self.books_menu then
		return
	end
	self:rebuildBooksMenuItems()
	self.books_menu:updateItems()
end

function UI:getBookCover(book)
	local cache_dir = DataStorage:getDataDir() .. "/cache/jellyfin/"
	util.makePath(cache_dir)

	local cover_path = cache_dir .. "cover_" .. book.Id .. ".jpg"
	if lfs.attributes(cover_path, "mode") == "file" then
		return cover_path
	end

	if not NetworkMgr:isOnline() then
		return nil
	end

	local success = self.api:downloadBookCover(book.Id, cover_path)
	if success then
		return cover_path
	end
	return nil
end

function UI:showBookActions(book)
	logger.info("Jellyfin: Showing actions for book:", book.Name)

	local is_played = book.UserData and book.UserData.Played
	local cover_path = self:getBookCover(book)
	local overview = bookOverviewText(book)

	local dialog

	local buttons = {}

	if overview then
		table.insert(buttons, {
			{
				text = _("Description"),
				callback = function()
					UIManager:close(dialog)
					UIManager:show(TextViewer:new {
						title = book.Name,
						text = overview,
					})
				end,
			},
		})
	end

	table.insert(buttons, {
		{
			text = _("Download"),
			callback = function()
				UIManager:close(dialog)
				self:downloadBook(book)
			end,
		},
		{
			text = is_played and _("Mark as Unread") or _("Mark as Read"),
			callback = function()
				UIManager:close(dialog)
				self:toggleReadStatus(book)
			end,
		},
	})

	table.insert(buttons, {
		{
			text = _("Cancel"),
			callback = function()
				UIManager:close(dialog)
			end,
		},
	})

	dialog = BookActionsDialog:new {
		width = math.floor(Screen:getWidth() * 0.75),
		cover_path = cover_path,
		cover_width = Screen:scaleBySize(170),
		cover_height = Screen:scaleBySize(225),
		book_name = book.Name,
		info_text = bookInfoText(book),
		buttons = buttons,
	}

	UIManager:show(dialog)
	self:refreshBooksMenu()
end

function UI:downloadBook(book)
	logger.info("Jellyfin: Starting download for book:", book.Name, "ID:", book.Id)

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
		local download_dir = self.config:getDownloadDir()

		util.makePath(download_dir)

		-- Record an absolute path so the book-map key also matches when KOReader reopens the book via the file manager or history.
		local filepath = download_dir .. filename
		local absolute_dir = FFIUtil.realpath(download_dir)
		if absolute_dir then
			filepath = absolute_dir .. "/" .. filename
		end

		UIManager:show(InfoMessage:new {
			text = T(_("Downloading %1..."), book.Name),
			timeout = 2,
		})

		local success, error = self.api:downloadItem(book.Id, filepath)

		if success then
			local book_map = self.config:getBookMap()
			book_map[filepath] = {
				item_id = book.Id,
				name = book.Name,
			}
			self.config:setBookMap(book_map)

			UIManager:show(ConfirmBox:new {
				text = T(_("Book downloaded to:\n%1\n\nOpen now?"), filepath),
				ok_callback = function()
					local ReaderUI = require("apps/reader/readerui")
					ReaderUI:showReader(filepath)
				end,
			})
		else
			logger.err("Jellyfin: Download failed:", error)
			self:handleApiError(error, _("Failed to download book"))
		end
	end)
end

function UI:toggleReadStatus(book)
	logger.info("Jellyfin: Toggling read status for book:", book.Name)

	NetworkMgr:runWhenOnline(function()
		local is_played = book.UserData and book.UserData.Played

		UIManager:show(InfoMessage:new {
			text = _("Updating status..."),
			timeout = 1,
		})

		local success, error = self.api:setPlayedStatus(book.Id, not is_played)

		if success then
			if book.UserData then
				book.UserData.Played = not is_played
			end
			self:refreshBooksMenu()
			UIManager:show(InfoMessage:new {
				text = is_played and _("Marked as unread") or _("Marked as read"),
			})
		else
			logger.err("Jellyfin: Update status failed:", error)
			self:handleApiError(error, _("Failed to update status"))
		end
	end)
end

return UI
