--[[--
Jellyfin API client
@module koplugin.jellyfin.api
]]

local http = require("socket.http")
local ltn12 = require("ltn12")
local logger = require("logger")

-- JSON library with fallback
local json
local ok = pcall(function() json = require("json") end)
if not ok then
	json = require("rapidjson")
end

local API = {}

function API:new(config)
	local o = {
		config = config
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

function API:getAuthHeader()
	return string.format(
		'MediaBrowser Client="KOReader", Device="eReader", DeviceId="%s", Version="1.0.0"',
		self.config:getDeviceId()
	)
end

function API:authenticateByPassword(username, password)
	local auth_url = self.config:getServerUrl() .. "/Users/AuthenticateByName"
	local auth_data = json.encode({
		Username = username,
		Pw = password,
	})

	local response_body = {}

	local res, code = http.request {
		url = auth_url,
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Content-Length"] = tostring(#auth_data),
			["X-Emby-Authorization"] = self:getAuthHeader(),
		},
		source = ltn12.source.string(auth_data),
		sink = ltn12.sink.table(response_body),
	}

	if code == 200 then
		local response = json.decode(table.concat(response_body))
		return true, response
	else
		return false, code
	end
end

function API:initiateQuickConnect()
	local qc_url = self.config:getServerUrl() .. "/QuickConnect/Initiate"
	local response_body = {}

	local res, code = http.request {
		url = qc_url,
		method = "POST",
		headers = {
			["X-Emby-Authorization"] = self:getAuthHeader(),
		},
		sink = ltn12.sink.table(response_body),
	}

	if code == 200 then
		local response = json.decode(table.concat(response_body))
		return true, response
	else
		return false, code
	end
end

function API:checkQuickConnect(secret)
	local check_url = self.config:getServerUrl() .. "/QuickConnect/Connect?secret=" .. secret
	local response_body = {}

	local res, code = http.request {
		url = check_url,
		method = "GET",
		headers = {
			["X-Emby-Authorization"] = self:getAuthHeader(),
		},
		sink = ltn12.sink.table(response_body),
	}

	if code == 200 then
		local response = json.decode(table.concat(response_body))
		return true, response
	else
		return false, code
	end
end

function API:authenticateWithQuickConnect(secret)
	local auth_url = self.config:getServerUrl() .. "/Users/AuthenticateWithQuickConnect"
	local auth_data = json.encode({
		Secret = secret,
	})

	local response_body = {}

	local res, code = http.request {
		url = auth_url,
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Content-Length"] = tostring(#auth_data),
			["X-Emby-Authorization"] = self:getAuthHeader(),
		},
		source = ltn12.source.string(auth_data),
		sink = ltn12.sink.table(response_body),
	}

	if code == 200 then
		local response = json.decode(table.concat(response_body))
		return true, response
	else
		return false, code
	end
end

function API:getUserViews()
	local user_id = self.config:getUserId()
	local views_url = self.config:getServerUrl() .. "/Users/" .. user_id .. "/Views"
	local response_body = {}

	logger.info("Jellyfin API: Request URL:", views_url)

	local res, code = http.request {
		url = views_url,
		method = "GET",
		headers = {
			["X-Emby-Token"] = self.config:getAccessToken(),
		},
		sink = ltn12.sink.table(response_body),
	}

	logger.info("Jellyfin API: Views response code:", code)

	if code == 200 then
		local ok, response = pcall(json.decode, table.concat(response_body))
		if ok then
			return true, response
		else
			return false, "parse_error"
		end
	else
		return false, code
	end
end

function API:getItemsInLibrary(library_id)
	local items_url = self.config:getServerUrl() .. "/Users/" .. self.config:getUserId() .. "/Items" ..
		"?ParentId=" .. library_id ..
		"&Recursive=true" ..
		"&Fields=Path,MediaSources" ..
		"&IncludeItemTypes=Book"

	logger.info("Jellyfin API: Fetching items from:", items_url)
	local response_body = {}

	local res, code = http.request {
		url = items_url,
		method = "GET",
		headers = {
			["X-Emby-Token"] = self.config:getAccessToken(),
		},
		sink = ltn12.sink.table(response_body),
	}

	logger.info("Jellyfin API: Items response code:", code)

	if code == 200 then
		local ok, response = pcall(json.decode, table.concat(response_body))
		if ok then
			return true, response
		else
			return false, "parse_error"
		end
	else
		return false, code
	end
end

function API:downloadItem(item_id, filepath)
	local download_url = self.config:getServerUrl() .. "/Items/" .. item_id .. "/Download"

	local file = io.open(filepath, "wb")
	if not file then
		return false, "file_error"
	end

	local res, code = http.request {
		url = download_url,
		method = "GET",
		headers = {
			["X-Emby-Token"] = self.config:getAccessToken(),
		},
		sink = ltn12.sink.file(file),
	}

	if io.type(file) == "file" then
		file:close()
	end

	if code == 200 then
		return true
	else
		os.remove(filepath)
		return false, code
	end
end

function API:setPlayedStatus(item_id, played)
	local endpoint = played and "PlayedItems" or "UnplayedItems"
	local status_url = self.config:getServerUrl() .. "/Users/" .. self.config:getUserId() ..
		"/" .. endpoint .. "/" .. item_id

	local res, code = http.request {
		url = status_url,
		method = "POST",
		headers = {
			["X-Emby-Token"] = self.config:getAccessToken(),
			["Content-Length"] = "0",
		},
	}

	return code == 200, code
end

return API
