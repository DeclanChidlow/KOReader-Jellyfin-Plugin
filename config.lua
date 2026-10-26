local DataStorage = require("datastorage")
local logger = require("logger")

local Config = {}

function Config:getServerUrl()
	return G_reader_settings:readSetting("jellyfin_server_url") or ""
end

function Config:setServerUrl(url)
	G_reader_settings:saveSetting("jellyfin_server_url", url)
end

function Config:getUserId()
	return G_reader_settings:readSetting("jellyfin_user_id") or ""
end

function Config:setUserId(user_id)
	G_reader_settings:saveSetting("jellyfin_user_id", user_id)
end

function Config:getAccessToken()
	return G_reader_settings:readSetting("jellyfin_access_token") or ""
end

function Config:setAccessToken(token)
	G_reader_settings:saveSetting("jellyfin_access_token", token)
end

function Config:getDeviceId()
	return G_reader_settings:readSetting("device_id") or ""
end

function Config:setDeviceId(device_id)
	G_reader_settings:saveSetting("device_id", device_id)
end

function Config:clearAuth()
	G_reader_settings:delSetting("jellyfin_access_token")
	G_reader_settings:delSetting("jellyfin_user_id")
	G_reader_settings:delSetting("jellyfin_book_map")
end

function Config:isLoggedIn()
	return self:getAccessToken() ~= ""
end

function Config:getBookMap()
	return G_reader_settings:readSetting("jellyfin_book_map") or {}
end

function Config:setBookMap(book_map)
	G_reader_settings:saveSetting("jellyfin_book_map", book_map)
end

function Config:getSyncEnabled()
	return G_reader_settings:isTrue("jellyfin_sync_progress")
end

function Config:setSyncEnabled(enabled)
	G_reader_settings:saveSetting("jellyfin_sync_progress", enabled)
end

function Config:getTopMenuTabEnabled()
    return G_reader_settings:isTrue("jellyfin_top_menu_tab_enabled")
end

function Config:setTopMenuTabEnabled(enabled)
    G_reader_settings:saveSetting("jellyfin_top_menu_tab_enabled", enabled)
end

function Config:getDownloadDir()
	local dir = G_reader_settings:readSetting("jellyfin_download_dir")
	if not dir or dir == "" then
		local data_dir = DataStorage:getFullDataDir() or DataStorage:getDataDir()
		return data_dir .. "/books/"
	end
	return dir
end

function Config:setDownloadDir(dir)
	dir = dir:gsub("^%s+", ""):gsub("%s+$", "")
	if dir ~= "" and dir:sub(-1) ~= "/" then
		dir = dir .. "/"
	end
	G_reader_settings:saveSetting("jellyfin_download_dir", dir)
end

function Config:resetDownloadDir()
	G_reader_settings:delSetting("jellyfin_download_dir")
end

function Config:getBookSort()
	return G_reader_settings:readSetting("jellyfin_book_sort") or "title"
end

function Config:setBookSort(sort_key)
	G_reader_settings:saveSetting("jellyfin_book_sort", sort_key)
end

function Config:getBookSortOrder()
	return G_reader_settings:readSetting("jellyfin_book_sort_order") or "asc"
end

function Config:setBookSortOrder(sort_order)
	G_reader_settings:saveSetting("jellyfin_book_sort_order", sort_order)
end

function Config:getBookFilter()
	return G_reader_settings:readSetting("jellyfin_book_filter") or "all"
end

function Config:setBookFilter(filter_key)
	G_reader_settings:saveSetting("jellyfin_book_filter", filter_key)
end

function Config:initialize()
	logger.info("Jellyfin Config: Initialising settings")

	if not G_reader_settings:readSetting("jellyfin_server_url") then
		G_reader_settings:saveSetting("jellyfin_server_url", "")
	end
	if not G_reader_settings:readSetting("jellyfin_user_id") then
		G_reader_settings:saveSetting("jellyfin_user_id", "")
	end
	if not G_reader_settings:readSetting("jellyfin_access_token") then
		G_reader_settings:saveSetting("jellyfin_access_token", "")
	end
	if not G_reader_settings:readSetting("jellyfin_book_map") then
		G_reader_settings:saveSetting("jellyfin_book_map", {})
	end
	if not G_reader_settings:has("jellyfin_sync_progress") then
		G_reader_settings:saveSetting("jellyfin_sync_progress", true)
	end
	if not G_reader_settings:has("jellyfin_top_menu_tab_enabled") then
		G_reader_settings:saveSetting("jellyfin_top_menu_tab_enabled", false)
	end
	if not G_reader_settings:has("jellyfin_book_sort") then
		G_reader_settings:saveSetting("jellyfin_book_sort", "title")
	end
	if not G_reader_settings:has("jellyfin_book_sort_order") then
		G_reader_settings:saveSetting("jellyfin_book_sort_order", "asc")
	end
	if not G_reader_settings:has("jellyfin_book_filter") then
		G_reader_settings:saveSetting("jellyfin_book_filter", "all")
	end

	if not G_reader_settings:readSetting("device_id") then
		local device_id = "koreader_" .. os.time() .. "_" .. math.random(1000, 9999)
		G_reader_settings:saveSetting("device_id", device_id)
	end
end

return Config
