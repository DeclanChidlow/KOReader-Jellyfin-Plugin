-- QuickTab menu registration tests.
-- Run from repository root: lua tests/test_quicktab.lua

package.loaded["gettext"] = function(s) return s end

local order = {
    ["KOMenu:menu_buttons"] = {
        "filemanager_settings", "setting",
        "tools", "search", "plus_menu", "main",
    },
}
package.loaded["ui/elements/filemanager_menu_order"] = order

local QuickTab = dofile("quicktab.lua")
local enabled = false
local config = {
    getQuickTabEnabled = function()
        return enabled
    end,
}

local function makeMenu()
    local items = {
        filemanager_settings = {},
        jellyfin = {
            text = "Jellyfin",
            sorting_hint = "tools",
            sub_item_table = {
                { text = "Configure Server", callback = function() end },
                { text = "Browse Books", callback = function() end },
                { text = "Sync reading progress",
                  checked_func = function() return true end },
                { text = "Enable Jellyfin QuickTab (restart required)",
                  callback = function() end },
            },
        },
    }
    return items
end

-- Disabled by default.
local menu = makeMenu()
QuickTab.addToMainMenu(menu, config)
assert(menu.jellyfin_quicktab == nil)
assert(order.jellyfin_quicktab == nil)
print("PASS: Disabled QuickTab")

-- Do not add a tab outside the file manager.
enabled = true
menu = makeMenu()
menu.filemanager_settings = nil
QuickTab.addToMainMenu(menu, config)
assert(menu.jellyfin_quicktab == nil)
print("PASS: File manager only")

-- Missing Jellyfin menu should be harmless.
QuickTab.addToMainMenu({ filemanager_settings = {} }, config)
print("PASS: Missing Jellyfin menu")

-- Enabled: full menu, with Browse Books first.
menu = makeMenu()
local original = menu.jellyfin
local original_items = original.sub_item_table

QuickTab.addToMainMenu(menu, config)

assert(menu.jellyfin_quicktab)
assert(#order.jellyfin_quicktab == #original_items)

local first_id = order.jellyfin_quicktab[1]
assert(menu[first_id].text == "Browse Books")
assert(menu[first_id].callback == original_items[2].callback)
print("PASS: Browse Books first")

-- Other actions must also be present.
for _, item in ipairs(original_items) do
    local found = false
    for _, id in ipairs(order.jellyfin_quicktab) do
        if menu[id].text == item.text then
            found = true
            break
        end
    end
    assert(found, "Missing menu item: " .. item.text)
end
print("PASS: Complete Jellyfin menu")

-- Original Tools entry must remain untouched.
assert(menu.jellyfin == original)
assert(menu.jellyfin.sorting_hint == "tools")
assert(menu.jellyfin.sub_item_table == original_items)
print("PASS: Original Tools menu preserved")

-- Repeated registration must not duplicate the tab.
QuickTab.addToMainMenu(menu, config)
local count = 0
for _, id in ipairs(order["KOMenu:menu_buttons"]) do
    if id == "jellyfin_quicktab" then
        count = count + 1
    end
end
assert(count == 1)
print("PASS: No duplicate QuickTab")

-- Use the bundled icon when installation succeeds.
local with_icon = makeMenu()
QuickTab.addToMainMenu(with_icon, config, true)

assert(with_icon.jellyfin_quicktab.icon == "jellyfin-quicktab")
print("PASS: Custom QuickTab icon selected")

-- Fall back to the built-in icon if installation fails.
local without_icon = makeMenu()
QuickTab.addToMainMenu(without_icon, config, false)

assert(without_icon.jellyfin_quicktab.icon == "appbar.tools")
print("PASS: Icon fallback")

print("All QuickTab menu tests passed.")
