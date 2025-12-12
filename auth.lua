--[[--
Jellyfin authentication handlers
@module koplugin.jellyfin.auth
]]

local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local FFIUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = FFIUtil.template

local Auth = {}

function Auth:new(config, api)
	local o = {
		config = config,
		api = api
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Auth:loginWithPassword()
	if self.config:getServerUrl() == "" then
		UIManager:show(InfoMessage:new {
			text = _("Please configure server URL first"),
		})
		return
	end

	NetworkMgr:runWhenOnline(function()
		local login_dialog
		login_dialog = MultiInputDialog:new {
			title = _("Login to Jellyfin"),
			fields = {
				{
					text = "",
					hint = _("Username"),
				},
				{
					text = "",
					hint = _("Password"),
					text_type = "password",
				},
			},
			buttons = {
				{
					{
						text = _("Cancel"),
						callback = function()
							UIManager:close(login_dialog)
						end,
					},
					{
						text = _("Login"),
						is_enter_default = true,
						callback = function()
							local fields = login_dialog:getFields()
							UIManager:close(login_dialog)
							self:performPasswordLogin(fields[1], fields[2])
						end,
					},
				},
			},
		}
		UIManager:show(login_dialog)
		login_dialog:onShowKeyboard()
	end)
end

function Auth:performPasswordLogin(username, password)
	UIManager:show(InfoMessage:new {
		text = _("Logging in..."),
		timeout = 1,
	})

	local success, result = self.api:authenticateByPassword(username, password)

	if success then
		self.config:setAccessToken(result.AccessToken)
		self.config:setUserId(result.User.Id)
		G_reader_settings:flush()

		logger.info("Jellyfin Auth: Logged in successfully, token saved")

		UIManager:show(InfoMessage:new {
			text = T(_("Logged in as %1"), result.User.Name),
		})
	else
		logger.err("Jellyfin Auth: Login failed:", result)
		UIManager:show(InfoMessage:new {
			text = T(_("Login failed (code %1)"), result),
		})
	end
end

function Auth:loginWithQuickConnect()
	if self.config:getServerUrl() == "" then
		UIManager:show(InfoMessage:new {
			text = _("Please configure server URL first"),
		})
		return
	end

	NetworkMgr:runWhenOnline(function()
		self:initiateQuickConnect()
	end)
end

function Auth:initiateQuickConnect()
	UIManager:show(InfoMessage:new {
		text = _("Initiating Quick Connect..."),
		timeout = 1,
	})

	local success, result = self.api:initiateQuickConnect()

	if success then
		self:showQuickConnectCode(result.Code, result.Secret)
	else
		logger.err("Jellyfin Auth: Quick Connect failed:", result)
		UIManager:show(InfoMessage:new {
			text = T(_("Quick Connect failed (code %1). Ensure it's enabled on your server."), result),
		})
	end
end

function Auth:showQuickConnectCode(code, secret)
	local button_dialog
	button_dialog = ButtonDialog:new {
		title = T(_("Enter this code in Jellyfin:\n\n%1\n\nWaiting for authorisation..."), code),
		buttons = {
			{
				{
					text = _("Cancel"),
					callback = function()
						UIManager:close(button_dialog)
					end,
				},
			},
		},
	}
	UIManager:show(button_dialog)

	self:pollQuickConnect(secret, button_dialog)
end

function Auth:pollQuickConnect(secret, dialog)
	local success, result = self.api:checkQuickConnect(secret)

	if success then
		if result.Authenticated then
			UIManager:close(dialog)
			self:completeQuickConnect(secret)
		else
			UIManager:scheduleIn(2, function()
				if dialog then
					self:pollQuickConnect(secret, dialog)
				end
			end)
		end
	else
		UIManager:close(dialog)
		UIManager:show(InfoMessage:new {
			text = T(_("Quick Connect check failed (code %1)"), result),
		})
	end
end

function Auth:completeQuickConnect(secret)
	local success, result = self.api:authenticateWithQuickConnect(secret)

	if success then
		self.config:setAccessToken(result.AccessToken)
		self.config:setUserId(result.User.Id)
		G_reader_settings:flush()

		logger.info("Jellyfin Auth: Quick Connect authentication successful, token saved")

		UIManager:show(InfoMessage:new {
			text = T(_("Logged in as %1"), result.User.Name),
		})
	else
		logger.err("Jellyfin Auth: Quick Connect auth failed:", result)
		UIManager:show(InfoMessage:new {
			text = T(_("Authentication failed (code %1)"), result),
		})
	end
end

function Auth:logout()
	self.config:clearAuth()

	UIManager:show(InfoMessage:new {
		text = _("Logged out successfully"),
	})
end

return Auth
