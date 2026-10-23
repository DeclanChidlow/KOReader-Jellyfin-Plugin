-- Regression tests for Jellyfin book path mapping.
-- Run with: lua tests/test_book_mapping.lua

local base = "/mnt/us/koreader"

local function stub(name, value)
	package.loaded[name] = value
end

stub("ui/widget/container/widgetcontainer", {
	extend = function(_, definition)
		return definition
	end,
})

stub("ui/widget/confirmbox", {})
stub("ui/network/manager", {})
stub("ui/uimanager", {})
stub("logger", {})
stub("gettext", function(s) return s end)

local existing_paths = {}

local function normalize(path)
	if path:sub(1, 1) ~= "/" then
		path = base .. "/" .. path
	end
	path = path:gsub("/+", "/")
	path = path:gsub("/%./", "/")
	return path
end

stub("ffi/util", {
	template = function(s) return s end,
	realpath = function(path)
		-- Simulate realpath: canonicalise existing paths, fail for missing ones.
		path = normalize(path)
		if existing_paths[path] then
			return path
		end
		return nil
	end,
})

local DataStorage = {
	getFullDataDir = function()
		return base
	end,
	getDataDir = function()
		return "."
	end,
}

stub("datastorage", DataStorage)

local book = {
	item_id = "test-jellyfin-book-id",
	name = "Test Book",
}

local book_map = {}

stub("config", {
	getBookMap = function()
		return book_map
	end,
	setBookMap = function(_, map)
		book_map = map
	end,
})

stub("api", {})
stub("auth", {})
stub("ui", {})

local Jellyfin = dofile("main.lua")

local function mappedBook(stored_path, opened_path, options)
	options = options or {}
	book_map = {
		[stored_path] = book,
	}

	existing_paths = {}
	if options.mark_stored ~= false then
		existing_paths[normalize(stored_path)] = true
	end
	if options.mark_opened ~= false then
		existing_paths[normalize(opened_path)] = true
	end

	local instance = {
		ui = {
			document = {
				file = opened_path,
			},
		},
	}
	setmetatable(instance, { __index = Jellyfin })

	return instance:getMappedBook(), instance
end

local function check(label, stored_path, opened_path, migrated_path)
	local result = mappedBook(stored_path, opened_path)
	assert(result == book, label .. " failed")
	if migrated_path then
		assert(book_map[migrated_path] == book,
			label .. " did not migrate the map key")
	end
	print("PASS: " .. label)
end

check(
	"Relative download path",
	"./books/Test Book.epub",
	base .. "/books/Test Book.epub",
	base .. "/books/Test Book.epub"
)

check(
	"Existing absolute path",
	base .. "/books/Test Book.epub",
	base .. "/books/Test Book.epub"
)

check(
	"Relative reader path",
	base .. "/books/Test Book.epub",
	"./books/Test Book.epub"
)

check(
	"Path containing dot component",
	base .. "/./books/Test Book.epub",
	base .. "/books/Test Book.epub",
	base .. "/books/Test Book.epub"
)

-- An unrelated book must not match.
assert(mappedBook(
	"./books/Another Book.epub",
	base .. "/books/Test Book.epub"
) == nil, "Unrelated book must not match")
print("PASS: Unrelated book does not match")

-- If the document path cannot be resolved, no mapping should be returned,
-- even when some stored paths are equally unresolvable.
assert(mappedBook(
	"./books/Test Book.epub",
	base .. "/books/Missing Book.epub",
	{ mark_opened = false }
) == nil, "Unresolvable document path must not match")
print("PASS: Unresolvable document path does not match")

-- A missing data directory must not raise when resolving a relative path.
local original_get_full_data_dir = DataStorage.getFullDataDir
DataStorage.getFullDataDir = function()
	return nil
end

local ok, result = pcall(
	mappedBook,
	base .. "/books/Test Book.epub",
	"./books/Test Book.epub"
)

DataStorage.getFullDataDir = original_get_full_data_dir

assert(ok, "Unresolvable data directory raised an error: " .. tostring(result))
assert(result == nil, "Unresolvable data directory must not match")
print("PASS: Unresolvable data directory does not match")

-- The default download directory should be absolute when possible.
local download_dir_setting

G_reader_settings = {
	readSetting = function(_, key)
		if key == "jellyfin_download_dir" then
			return download_dir_setting
		end
		return nil
	end,
}

local Config = dofile("config.lua")

download_dir_setting = nil
assert(Config:getDownloadDir() == base .. "/books/",
	"Default download directory should be absolute")
print("PASS: Default download directory is absolute")

download_dir_setting = "/custom/books/"
assert(Config:getDownloadDir() == "/custom/books/",
	"Configured download directory should be preserved")
print("PASS: Configured download directory is preserved")

DataStorage.getFullDataDir = function()
	return nil
end

download_dir_setting = nil
assert(Config:getDownloadDir() == "./books/",
	"Default download directory should fall back to the relative data dir")
print("PASS: Default download directory falls back safely")

DataStorage.getFullDataDir = original_get_full_data_dir

print("All book mapping tests passed.")
