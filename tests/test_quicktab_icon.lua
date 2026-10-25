package.loaded["gettext"] = function(s) return s end

local temp = os.tmpname()
os.remove(temp)

local function quoted(path)
    return string.format("%q", path)
end

local function isdir(path)
    return os.execute("test -d " .. quoted(path)) == true
end

assert(os.execute("mkdir " .. quoted(temp)))

package.loaded["datastorage"] = {
    getDataDir = function()
        return temp
    end,
}

package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path, attribute)
        if attribute == "mode" and isdir(path) then
            return "directory"
        end
    end,
    mkdir = function(path)
        return os.execute("mkdir " .. quoted(path))
    end,
}

local QuickTab = require("quicktab")

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local target = temp .. "/icons/jellyfin-quicktab.svg"
local source = "icons/jellyfin-quicktab.svg"

assert(QuickTab.installIcon(), "Icon installation failed")
assert(readFile(target) == readFile(source))
print("PASS: Icon installed correctly")

assert(QuickTab.installIcon(), "Repeated installation failed")
assert(readFile(target) == readFile(source))
print("PASS: Repeated installation")

local file = assert(io.open(target, "wb"))
file:write("outdated icon")
file:close()

assert(QuickTab.installIcon(), "Icon update failed")
assert(readFile(target) == readFile(source))
print("PASS: Outdated icon replaced")

assert(os.remove(target))
assert(os.execute("rmdir " .. quoted(temp .. "/icons")))
assert(os.execute("rmdir " .. quoted(temp)))

print("All QuickTab icon tests passed.")
