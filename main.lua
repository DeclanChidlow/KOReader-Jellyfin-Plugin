--[[--
Jellyfin plugin for KOReader
Download books from Jellyfin server and mark them as read
@module koplugin.jellyfin
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Config = require("config")
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
	self.api = API:new(Config)
	self.auth = Auth:new(Config, self.api)
	self.ui_handler = UI:new(Config, self.api)
	self.ui.menu:registerToMainMenu(self)
	logger.info("Jellyfin: Plugin initialised")
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
				text = _("Logout"),
				enabled_func = function()
					return Config:isLoggedIn()
				end,
				callback = function()
					self.auth:logout()
				end,
			},
		},
	}
end

return Jellyfin
