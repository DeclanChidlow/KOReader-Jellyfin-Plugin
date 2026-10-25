-- Regression tests for the optional Jellyfin QuickTab setting.
-- Run with: lua tests/test_quicktab_config.lua

package.loaded["datastorage"] = {}
package.loaded["logger"] = {
    info = function() end,
}

local settings = {}

G_reader_settings = {
    readSetting = function(_, key)
        return settings[key]
    end,
    saveSetting = function(_, key, value)
        settings[key] = value
    end,
    has = function(_, key)
        return settings[key] ~= nil
    end,
    isTrue = function(_, key)
        return settings[key] == true
    end,
}

local Config = dofile("config.lua")

-- Default: disabled.
Config:initialize()
assert(Config:getQuickTabEnabled() == false)
assert(settings.jellyfin_quicktab_enabled == false)
print("PASS: QuickTab disabled by default")

-- Enabling persists.
Config:setQuickTabEnabled(true)
assert(Config:getQuickTabEnabled() == true)
print("PASS: QuickTab can be enabled")

-- Initialization must preserve an existing preference.
Config:initialize()
assert(Config:getQuickTabEnabled() == true)
print("PASS: Enabled setting survives initialization")

-- Disabling persists.
Config:setQuickTabEnabled(false)
assert(Config:getQuickTabEnabled() == false)
print("PASS: QuickTab can be disabled")

-- Existing sync settings remain unaffected.
assert(settings.jellyfin_sync_progress == true)
print("PASS: Existing sync setting preserved")

print("All QuickTab configuration tests passed.")
