-- QuickTab regression tests.
-- Run with: lua tests/test_quicktab.lua

package.loaded["gettext"] = function(s) return s end
package.loaded["datastorage"] = {}
package.loaded["logger"] = { info = function() end }

local settings = {}
G_reader_settings = {
	readSetting = function(_, key) return settings[key] end,
	saveSetting = function(_, key, value) settings[key] = value end,
	has = function(_, key) return settings[key] ~= nil end,
	isTrue = function(_, key) return settings[key] == true end,
}

local order = {
	["KOMenu:menu_buttons"] = {
		"filemanager_settings", "setting",
		"tools", "search", "plus_menu", "main",
	},
}
package.loaded["ui/elements/filemanager_menu_order"] = order

local Config = dofile("config.lua")
local QuickTab = dofile("quicktab.lua")

local function makeMenu()
	return {
		filemanager_settings = {},
		jellyfin = {
			sub_item_table = {
				{ text = "Configure Server" },
				{ text = "Browse Books" },
			},
		},
	}
end

Config:initialize()
assert(Config:getQuickTabEnabled() == false, "QuickTab should be disabled by default")

local menu = makeMenu()
QuickTab.addToMainMenu(menu, Config)
assert(menu.jellyfin_quicktab == nil, "QuickTab should not be added when disabled")

Config:setQuickTabEnabled(true)
menu = makeMenu()
QuickTab.addToMainMenu(menu, Config)

assert(menu.jellyfin_quicktab, "QuickTab should be added when enabled")
assert(#order.jellyfin_quicktab == 2, "QuickTab should contain every Jellyfin action")
assert(menu[order.jellyfin_quicktab[1]].text == "Browse Books",
	"Browse Books should come first")
assert(#menu.jellyfin.sub_item_table == 2, "Original Jellyfin menu should be unchanged")

print("All QuickTab tests passed.")
