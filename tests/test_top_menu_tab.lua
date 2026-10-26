-- Top menu tab regression tests.
-- Run with: lua tests/test_top_menu_tab.lua

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
local TopMenuTab = dofile("top_menu_tab.lua")

local function makeMenu()
	return {
		filemanager_settings = {},
		jellyfin = {
			sub_item_table = {
				{ text = "Browse Books" },
				{ text = "Configure Server" },
			},
		},
	}
end

Config:initialize()
assert(Config:getTopMenuTabEnabled() == false, "Top menu tab should be disabled by default")

local menu = makeMenu()
TopMenuTab.addToMainMenu(menu, Config)
assert(menu.jellyfin_top_menu_tab == nil, "Top menu tab should not be added when disabled")

Config:setTopMenuTabEnabled(true)
menu = makeMenu()
TopMenuTab.addToMainMenu(menu, Config)

assert(menu.jellyfin_top_menu_tab, "Top menu tab should be added when enabled")
assert(#order.jellyfin_top_menu_tab == 2, "Top menu tab should contain every Jellyfin action")
assert(menu[order.jellyfin_top_menu_tab[1]].text == "Browse Books",
	"Browse Books should come first")
assert(#menu.jellyfin.sub_item_table == 2, "Original Jellyfin menu should be unchanged")

print("All top menu tab tests passed.")
