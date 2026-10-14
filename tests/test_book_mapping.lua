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

stub("ffi/util", {
    template = function(s) return s end,
    realpath = function(path)
        -- Simulate canonical paths for existing test files.
        path = path:gsub("/%./", "/")
        return path
    end,
})

stub("datastorage", {
    getFullDataDir = function()
        return base
    end,
})

local book = {
    item_id = "test-jellyfin-book-id",
    name = "Test Book",
}

local book_map = {}

stub("config", {
    getBookMap = function()
        return book_map
    end,
})

stub("api", {})
stub("auth", {})
stub("ui", {})

local Jellyfin = dofile("main.lua")

local function check(label, stored_path, opened_path)
    book_map = {
        [stored_path] = book,
    }

    local instance = {
        ui = {
            document = {
                file = opened_path,
            },
        },
    }
    setmetatable(instance, { __index = Jellyfin })

    local result = instance:getMappedBook()
    assert(result == book, label .. " failed")
    print("PASS: " .. label)
end

check(
    "Relative download path",
    "./books/Test Book.epub",
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
    base .. "/books/Test Book.epub"
)

-- An unrelated book must not match.
book_map = {
    ["./books/Another Book.epub"] = book,
}

local instance = {
    ui = {
        document = {
            file = base .. "/books/Test Book.epub",
        },
    },
}

setmetatable(instance, { __index = Jellyfin })

assert(instance:getMappedBook() == nil,
    "Unrelated book must not match")

print("PASS: Unrelated book does not match")

print("All book mapping tests passed.")
