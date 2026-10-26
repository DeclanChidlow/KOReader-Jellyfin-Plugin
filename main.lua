local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = FFIUtil.template

local Config = require("config")
local QuickTab = require("quicktab")
local API = require("api")
local Auth = require("auth")
local UI = require("ui")

local Jellyfin = WidgetContainer:extend {
	name = "jellyfin",
	is_doc_only = false,
}

function Jellyfin:init()
	logger.info("Jellyfin: Initialising plugin")

	Config:initialize()
	self.quicktab_icon_available = QuickTab.installIcon()
	self.api = API:new(Config)
	self.auth = Auth:new(Config, self.api)
	self.ui_handler = UI:new(Config, self.api)
	self.progress_push_task = function()
		self:pushProgress()
	end
	self.ui.menu:registerToMainMenu(self)
	logger.info("Jellyfin: Plugin initialised")
end

function Jellyfin:shouldSyncProgress()
	return Config:isLoggedIn() and Config:getSyncEnabled()
end

local function absolutePath(path)
	if type(path) ~= "string" then
		return nil
	end

	if path:sub(1, 1) ~= "/" then
		local data_dir = DataStorage:getFullDataDir()
		if not data_dir then
			return nil
		end
		path = data_dir .. "/" .. path
	end

	return FFIUtil.realpath(path)
end

function Jellyfin:getMappedBook()
	local file = self.ui and self.ui.document and self.ui.document.file
	if not file then
		return nil
	end

	local book_map = Config:getBookMap()

	-- Preserve existing exact-path mappings.
	local entry = book_map[file]
	if entry then
		return entry
	end

	-- Support relative paths saved by v1.2.0 or lower or custom download folders.
	local absolute_file = absolutePath(file)
	if not absolute_file then
		return nil
	end

	local matched_path
	for path, candidate in pairs(book_map) do
		local mapped_path = absolutePath(path)
		if mapped_path and mapped_path == absolute_file then
			matched_path = path
			entry = candidate
			break
		end
	end

	if not entry then
		return nil
	end

	if matched_path ~= absolute_file then
		book_map[matched_path] = nil
		book_map[absolute_file] = entry
		Config:setBookMap(book_map)
	end

	return entry
end

function Jellyfin:getLocalProgress()
	local ui = self.ui
	if not ui or not ui.document then
		return nil
	end

	local footer = ui.view and ui.view.footer
	if footer and footer.percent_finished then
		return math.min(1, math.max(0, footer.percent_finished))
	end

	local document = ui.document
	local page = ui:getCurrentPage()
	if not page or page <= 0 then
		return nil
	end

	if document:hasHiddenFlows() then
		local flow = document:getPageFlow(page)
		local flow_page = document:getPageNumberInFlow(page)
		local flow_pages = document:getTotalPagesInFlow(flow)
		if flow_page and flow_pages and flow_pages > 0 then
			return math.min(1, flow_page / flow_pages)
		end
	end

	local total = document:getPageCount()
	if total and total > 0 then
		return math.min(1, page / total)
	end
	return nil
end

function Jellyfin:onPageUpdate(page)
	self:scheduleProgressPush()
end

function Jellyfin:onPosUpdate(pos, page)
	self:scheduleProgressPush()
end

function Jellyfin:scheduleProgressPush()
	if not self:shouldSyncProgress() or not self:getMappedBook() then
		return
	end

	UIManager:unschedule(self.progress_push_task)
	UIManager:scheduleIn(15, self.progress_push_task)
end

function Jellyfin:pushProgress()
	if not self:shouldSyncProgress() then
		return
	end

	local entry = self:getMappedBook()
	if not entry then
		return
	end

	local percent = self:getLocalProgress()
	if not percent then
		return
	end
	self.last_progress = percent

	if self.last_synced_progress == percent then
		return
	end

	if not NetworkMgr:isOnline() then
		return
	end

	local success, code = self.api:reportProgress(entry.item_id, percent)
	if success then
		self.last_synced_progress = percent
		logger.info("Jellyfin: Progress synced for", entry.name, "to", string.format("%d%%", math.floor(percent * 100)))
	else
		logger.warn("Jellyfin: Progress sync failed for", entry.name, "code:", code)
	end
end

function Jellyfin:onCloseDocument()
	UIManager:unschedule(self.progress_push_task)

	if not self:shouldSyncProgress() then
		return
	end

	local entry = self:getMappedBook()
	if not entry then
		return
	end

	local percent = self.last_progress or self:getLocalProgress()
	if not percent then
		return
	end

	if not NetworkMgr:isOnline() then
		return
	end

	logger.info("Jellyfin: Pushing final progress for", entry.name)
	local success, code = self.api:reportProgress(entry.item_id, percent)
	if not success then
		logger.warn("Jellyfin: Final progress sync failed for", entry.name, "code:", code)
	end
end

function Jellyfin:gotoPercent(percent)
	if self.ui.paging then
		self.ui.paging:onGotoPercent(percent)
	elseif self.ui.rolling then
		self.ui.rolling:onGotoPercent(percent)
	end
end

function Jellyfin:onReaderReady()
	if not self:shouldSyncProgress() then
		return
	end

	local entry = self:getMappedBook()
	if not entry then
		return
	end

	logger.info("Jellyfin: Checking server progress for", entry.name)

	local local_progress = self:getLocalProgress() or 0

	if not NetworkMgr:isOnline() then
		return
	end

	local success, userdata = self.api:getItemUserData(entry.item_id)
	if not success then
		logger.warn("Jellyfin: Failed to fetch server progress for", entry.name, "code:", userdata)
		return
	end

	local ticks = userdata.PlaybackPositionTicks
	if not ticks or ticks <= 0 then
		return
	end

	local server_progress = ticks / 10000000
	if server_progress <= 0 or server_progress > 1 then
		return
	end

	local ui = self.ui
	local document = ui and ui.document
	local total_pages = document and document:getPageCount()
	local current_page = ui and ui:getCurrentPage()
	if total_pages and total_pages > 0 and current_page then
		local target_page = math.floor(total_pages * server_progress)
		if target_page - current_page <= 1 then
			return
		end
	elseif server_progress - local_progress < 0.01 then
		return
	end

	local percent = math.min(100, math.max(1, math.floor(server_progress * 100)))
	logger.info("Jellyfin: Server progress for", entry.name, "is", percent, "% (local:", math.floor(local_progress * 100),
		"%)")

	UIManager:show(ConfirmBox:new {
		text = T(_("Resume reading %1 at %2% from your Jellyfin position?"), entry.name, percent),
		ok_text = _("Jump to Jellyfin position"),
		cancel_text = _("Stay at local position"),
		ok_callback = function()
			self:gotoPercent(percent)
		end,
	})
end

function Jellyfin:addToMainMenu(menu_items)
	logger.info("Jellyfin: Adding to main menu")

	menu_items.jellyfin = {
		text = _("Jellyfin"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text = _("Configure Server"),
				keep_menu_open = true,
				callback = function()
					self.ui_handler:configureServer()
				end,
			},
			{
				text = _("Login"),
				sub_item_table = {
					{
						text = _("Login with Password"),
						callback = function()
							self.auth:loginWithPassword()
						end,
					},
					{
						text = _("Login with Quick Connect"),
						callback = function()
							self.auth:loginWithQuickConnect()
						end,
					},
				},
			},
			{
				text = _("Browse Books"),
				enabled_func = function()
					return Config:isLoggedIn()
				end,
				callback = function()
					self.ui_handler:browseBooks()
				end,
			},
			{
				text = _("Sync reading progress"),
				enabled_func = function()
					return Config:isLoggedIn()
				end,
				checked_func = function()
					return Config:getSyncEnabled()
				end,
				keep_menu_open = true,
				callback = function()
					Config:setSyncEnabled(not Config:getSyncEnabled())
				end,
			},
			{
				text_func = function()
					return T(_("Download folder: %1"), Config:getDownloadDir())
				end,
				keep_menu_open = true,
				callback = function()
					self.ui_handler:configureDownloadDir()
				end,
			},
			{
				text = _("Logout"),
				enabled_func = function()
					return Config:isLoggedIn()
				end,
				callback = function()
					self.auth:logout()
				end,
			},
			{
				text = _("Show plugin on top menu"),
				checked_func = function()
					return Config:getQuickTabEnabled()
				end,
				keep_menu_open = true,
				callback = function()
					local enabled = not Config:getQuickTabEnabled()
					Config:setQuickTabEnabled(enabled)

					-- Only prompt when the setting no longer matches the menu state.
					if QuickTab.active ~= nil and enabled ~= QuickTab.active then
						UIManager:askForRestart(_("KOReader must restart to toggle the top menu tab."))
					end
				end,
			},
		},
	}
	QuickTab.addToMainMenu(menu_items, Config, self.quicktab_icon_available)
end

return Jellyfin
