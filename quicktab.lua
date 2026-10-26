local gettext = require("gettext")

local QuickTab = {
    -- Whether the tab is registered in the running file manager menu.
    -- nil until that menu has been built.
    active = nil,
}

function QuickTab.installIcon()
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")

    local source = debug.getinfo(1, "S").source
    local plugin_dir = source:match("^@(.*/)")

    if not plugin_dir then
        return false
    end

    local source_file = plugin_dir .. "icons/jellyfin-quicktab.svg"
    local target_dir = DataStorage:getDataDir() .. "/icons"
    local target_file = target_dir .. "/jellyfin-quicktab.svg"

    local input = io.open(source_file, "rb")
    if not input then
        return false
    end

    local contents = input:read("*a")
    input:close()

    if not contents or contents == "" then
        return false
    end

    if lfs.attributes(target_dir, "mode") ~= "directory" then
        if not lfs.mkdir(target_dir) then
            return false
        end
    end

    local existing = io.open(target_file, "rb")
    if existing then
        local current = existing:read("*a")
        existing:close()

        if current == contents then
            return true
        end
    end

    local temporary = target_file .. ".tmp"
    local output = io.open(temporary, "wb")
    if not output then
        return false
    end

    local written = output:write(contents)
    local closed = output:close()

    if not written or not closed then
        os.remove(temporary)
        return false
    end

    local renamed = os.rename(temporary, target_file)
    if not renamed then
        os.remove(temporary)
        return false
    end

    return true
end

function QuickTab.addToMainMenu(items, config, icon_available)
    -- Only show QuickTab in the file manager when enabled.
    if not items.filemanager_settings then
        return
    end

    if not config:getQuickTabEnabled() then
        QuickTab.active = false
        return
    end

    local jellyfin = items.jellyfin
    if not jellyfin or not jellyfin.sub_item_table then
        return
    end

    local order = require("ui/elements/filemanager_menu_order")
    local buttons = order["KOMenu:menu_buttons"]
    if not buttons then
        return
    end

    local ids = {}

    local function addItem(item)
        local id = "jellyfin_quicktab_item_" .. (#ids + 1)
        local copy = {}
        for key, value in pairs(item) do
            copy[key] = value
        end
        items[id] = copy
        table.insert(ids, id)
    end

    -- Show Browse Books first.
    for _, item in ipairs(jellyfin.sub_item_table) do
        if item.text == gettext("Browse Books") then
            addItem(item)
            break
        end
    end

    -- Followed by the remaining Jellyfin menu items.
    for _, item in ipairs(jellyfin.sub_item_table) do
        if item.text ~= gettext("Browse Books") then
            addItem(item)
        end
    end

    items.jellyfin_quicktab = {
         icon = icon_available and "jellyfin-quicktab" or "appbar.tools",
    }
    order.jellyfin_quicktab = ids
    QuickTab.active = true

    for _, id in ipairs(buttons) do
        if id == "jellyfin_quicktab" then
            return
        end
    end

    table.insert(buttons, 4, "jellyfin_quicktab")
end

return QuickTab
