-- Guda Equipment Sets Module
-- Detects and tracks equipment sets from Outfitter and ItemRack addons
-- Provides API for checking if items belong to equipment sets

local addon = Guda

local EquipmentSets = {}
addon.Modules.EquipmentSets = EquipmentSets

-- Internal state
local setData = {}       -- { setName => { itemIDs = {[itemID] = true} } }
local itemToSets = {}    -- { [itemID] => { setName1 = true, setName2 = true } }
local initialized = false
local outfitterReady = false
local itemRackReady = false
-- Content signature of the most recent FullScan, used to skip no-op refreshes
-- during the login polling loop. Declared at module scope so event callbacks
-- defined earlier in the file (HookOutfitterEvents) can invalidate it.
local lastScanSignature = nil

-------------------------------------------
-- Public API
-------------------------------------------

-- Check if an item ID belongs to any equipment set
function EquipmentSets:IsInSet(itemID)
    if not itemID then return false end
    return itemToSets[itemID] ~= nil
end

-- Get set names that contain a specific item ID
-- Returns a table of set names or nil
function EquipmentSets:GetSetNames(itemID)
    if not itemID then return nil end
    local sets = itemToSets[itemID]
    if not sets then return nil end

    local names = {}
    for name in pairs(sets) do
        table.insert(names, name)
    end
    if table.getn(names) == 0 then return nil end
    return names
end

-- Get all known set names (sorted)
function EquipmentSets:GetAllSetNames()
    local names = {}
    for name in pairs(setData) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-------------------------------------------
-- Internal: Rebuild item-to-set index
-------------------------------------------

local function RebuildItemIndex()
    itemToSets = {}
    for setName, data in pairs(setData) do
        if data.itemIDs then
            for itemID in pairs(data.itemIDs) do
                if not itemToSets[itemID] then
                    itemToSets[itemID] = {}
                end
                itemToSets[itemID][setName] = true
            end
        end
    end
end

-------------------------------------------
-- Outfitter Integration
-------------------------------------------

-- Outfitter groups outfits into four built-in categories (Outfitter.lua:112-117):
-- "Complete", "Partial" are user-assembled gear; "Accessory" is trinket/ring
-- swap buttons; "Special" is prefab convenience outfits. Only the first two
-- represent real equipment sets that belong as Guda bag categories.
local kIgnoredOutfitterCategories = {
    Accessory = true,
    Special = true,
}

-- Outfitter's globals can exist before its own internal tables are ready,
-- and API shapes differ between ports. Every call into Outfitter goes through
-- pcall so a partially-loaded or differently-versioned Outfitter downgrades
-- the scan to a no-op instead of aborting the whole addon's init chain.
local function ScanOutfitter()
    -- Check if Outfitter is loaded and initialized
    if not Outfitter_GetCategoryOrder then return false end

    addon:Debug("EquipmentSets: Scanning Outfitter outfits...")

    local ok, categoryOrder = pcall(Outfitter_GetCategoryOrder)
    if not ok then
        addon:Debug("EquipmentSets: Outfitter_GetCategoryOrder errored (%s); skipping Outfitter scan", tostring(categoryOrder))
        return false
    end
    if not categoryOrder then return false end

    local scannedSets = 0
    local scanOk, scanErr = pcall(function()
        for _, catID in ipairs(categoryOrder) do
            if not kIgnoredOutfitterCategories[catID] then
                local outfits = nil
                if Outfitter_GetOutfitsByCategoryID then
                    local gotOk, gotOutfits = pcall(Outfitter_GetOutfitsByCategoryID, catID)
                    if gotOk then outfits = gotOutfits end
                end
                if outfits then
                    for _, outfit in ipairs(outfits) do
                        local setName = outfit.Name
                        if setName and outfit.Items then
                            local itemIDs = {}
                            for slotName, item in pairs(outfit.Items) do
                                if item then
                                    local itemID = nil
                                    -- Outfitter stores item codes
                                    if item.Code then
                                        itemID = tonumber(item.Code)
                                    elseif item.ItemID then
                                        itemID = tonumber(item.ItemID)
                                    end
                                    if itemID and itemID > 0 then
                                        itemIDs[itemID] = true
                                    end
                                end
                            end

                            setData[setName] = { itemIDs = itemIDs, source = "Outfitter" }
                            scannedSets = scannedSets + 1
                        end
                    end
                end
            end
        end
    end)
    if not scanOk then
        addon:Debug("EquipmentSets: Outfitter scan errored (%s); partial results kept", tostring(scanErr))
    end

    addon:Debug("EquipmentSets: Scanned %d Outfitter outfits", scannedSets)
    return scannedSets > 0
end

local function HookOutfitterEvents()
    if not Outfitter_RegisterOutfitEvent then return end

    -- Outfitter has two generations of event names: the short form used by
    -- early releases ("EDIT") and the _OUTFIT suffixed form used by current
    -- builds including Ascension's ("EDIT_OUTFIT"). Registering for both is
    -- idempotent — whichever the installed Outfitter actually dispatches
    -- wakes our callback; the unused one is harmless.
    local events = {
        "ADD",  "DELETE",        "EDIT",         "RENAME",
        "ADD_OUTFIT", "DELETE_OUTFIT", "EDIT_OUTFIT", "DID_RENAME_OUTFIT",
    }
    for _, eventName in ipairs(events) do
        local success, err = pcall(function()
            Outfitter_RegisterOutfitEvent(eventName, function()
                addon:Debug("EquipmentSets: Outfitter event '%s', rescanning...", eventName)
                -- Force FullScan to treat this scan as changed even if the
                -- content signature happens to match what we saw last time
                -- (e.g. if Outfitter fired the event before fully mutating
                -- its outfit table). The signature check exists to suppress
                -- polling-loop thrash, not to swallow explicit user edits.
                lastScanSignature = nil
                if EquipmentSets.Rescan then EquipmentSets:Rescan() end
            end)
        end)
        if not success then
            addon:Debug("EquipmentSets: Failed to hook Outfitter event '%s': %s", eventName, tostring(err))
        end
    end
end

-------------------------------------------
-- ItemRack Integration
-------------------------------------------

local function ExtractItemRackID(value)
    -- Accepts a number, a bare-id string "12345", or an item link fragment
    -- like "item:12345:0:0:0". Returns numeric itemID or nil.
    if type(value) == "number" then
        return value > 0 and value or nil
    end
    if type(value) ~= "string" then return nil end
    local _, _, idStr = string.find(value, "item:(%d+)")
    if not idStr then
        _, _, idStr = string.find(value, "^(%d+)")
    end
    local itemID = tonumber(idStr)
    if itemID and itemID > 0 then return itemID end
    return nil
end

local function ScanItemRackStock(sets)
    -- Stock Gello ItemRack: ItemRackUser.Sets[name].equip[slot] = "itemID:..."
    -- Internal sets start with "~".
    local scanned = 0
    for setName, setInfo in pairs(sets) do
        if type(setName) == "string" and not string.find(setName, "^~") then
            local itemIDs = {}
            if type(setInfo) == "table" and setInfo.equip then
                for _, itemString in pairs(setInfo.equip) do
                    local itemID = ExtractItemRackID(itemString)
                    if itemID then itemIDs[itemID] = true end
                end
            end
            setData[setName] = { itemIDs = itemIDs, source = "ItemRack" }
            scanned = scanned + 1
        end
    end
    return scanned
end

local function ScanItemRackFork(sets)
    -- Turtle/Khalil ItemRack fork: Rack_User[user].Sets[name][slotNum] =
    -- { id = "item:<id>:<enchant>:<suffix>", name = "ItemName" }. Internal
    -- sets are prefixed "Rack-" or "ItemRack".
    local scanned = 0
    for setName, setInfo in pairs(sets) do
        if type(setName) == "string"
           and not string.find(setName, "^Rack%-")
           and not string.find(setName, "^ItemRack")
           and type(setInfo) == "table" then
            local itemIDs = {}
            for k, v in pairs(setInfo) do
                if type(k) == "number" and type(v) == "table" then
                    local itemID = ExtractItemRackID(v.id)
                    if itemID then itemIDs[itemID] = true end
                end
            end
            setData[setName] = { itemIDs = itemIDs, source = "ItemRack" }
            scanned = scanned + 1
        end
    end
    return scanned
end

local function IsItemRackLoaded()
    if ItemRackUser and ItemRackUser.Sets then return true end
    if Rack_User then
        local userKey = UnitName("player") .. " of " .. GetRealmName()
        if Rack_User[userKey] and Rack_User[userKey].Sets then return true end
    end
    return false
end

local function ScanItemRack()
    local scannedSets = 0

    if ItemRackUser and ItemRackUser.Sets then
        addon:Debug("EquipmentSets: Scanning ItemRack (stock) sets...")
        scannedSets = scannedSets + ScanItemRackStock(ItemRackUser.Sets)
    end

    if Rack_User then
        local userKey = UnitName("player") .. " of " .. GetRealmName()
        local userData = Rack_User[userKey]
        if userData and userData.Sets then
            addon:Debug("EquipmentSets: Scanning ItemRack (fork) sets for " .. userKey)
            scannedSets = scannedSets + ScanItemRackFork(userData.Sets)
        end
    end

    if scannedSets == 0 then return false end
    addon:Debug("EquipmentSets: Scanned %d ItemRack sets", scannedSets)
    return true
end

-------------------------------------------
-- Full Scan (all sources)
-------------------------------------------

local function CountSets()
    local n = 0
    for _ in pairs(setData) do n = n + 1 end
    return n
end

-- Content-signature of setData so we can detect real changes (set added/removed
-- OR item added/removed within a set) without relying on count alone. Cheap for
-- realistic input (a few sets × a handful of items each).
local function ComputeSetSignature()
    local names = {}
    for name in pairs(setData) do
        table.insert(names, name)
    end
    table.sort(names)

    local parts = {}
    for _, name in ipairs(names) do
        table.insert(parts, name)
        local ids = {}
        local info = setData[name]
        if info and info.itemIDs then
            for id in pairs(info.itemIDs) do
                table.insert(ids, id)
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            table.insert(parts, tostring(id))
        end
        table.insert(parts, "#")
    end
    return table.concat(parts, "|")
end

-- Returns the number of sets discovered. When the scan's signature differs
-- from the previous one (sets or items changed), also syncs EquipSet
-- categories and repaints any open bag/bank so lock icons / category marks
-- stay in sync without user interaction. Same-signature scans are cheap
-- no-ops — important because the polling frame can call us up to 30 times
-- during login before Outfitter finishes populating its outfit list.
local function FullScan()
    setData = {}

    local hasOutfitter = ScanOutfitter()
    local hasItemRack = ScanItemRack()

    RebuildItemIndex()

    local signature = ComputeSetSignature()
    local changed = (signature ~= lastScanSignature)
    lastScanSignature = signature

    if changed then
        -- Rebuild EquipSet:* category definitions (this also clears
        -- CategoryManager's result cache via SaveCategories → ClearCache).
        if addon.Modules.CategoryManager then
            addon.Modules.CategoryManager:SyncEquipmentSetCategories()
        end

        -- Repaint any open bag/bank so IsItemProtected and categoryMark pick
        -- up the fresh itemToSets. Safe during combat: both frames are
        -- already shown, so Update is a plain repaint — no protected-frame
        -- creation.
        if Guda_BagFrame and Guda_BagFrame.IsShown and Guda_BagFrame:IsShown()
           and addon.Modules.BagFrame and addon.Modules.BagFrame.Update then
            pcall(function() addon.Modules.BagFrame:Update() end)
        end
        if Guda_BankFrame and Guda_BankFrame.IsShown and Guda_BankFrame:IsShown()
           and addon.Modules.BankFrame and addon.Modules.BankFrame.Update then
            pcall(function() addon.Modules.BankFrame:Update() end)
        end
    end

    local setCount = CountSets()
    if hasOutfitter or hasItemRack then
        addon:Debug("EquipmentSets: Full scan complete, %d total sets (changed=%s)",
            setCount, tostring(changed))
    end

    return setCount
end

-------------------------------------------
-- Initialization
-------------------------------------------

function EquipmentSets:Initialize()
    if initialized then return end
    initialized = true

    -- Register for ADDON_LOADED to catch late-loading addons
    addon.Modules.Events:Register("ADDON_LOADED", function(event, addonName)
        if addonName == "Outfitter" then
            -- Outfitter needs its INIT event before scanning
            outfitterReady = true
            addon:Debug("EquipmentSets: Outfitter loaded, waiting for INIT...")
        elseif addonName == "ItemRack" then
            itemRackReady = true
            addon:Debug("EquipmentSets: ItemRack loaded, scanning...")
            FullScan()
        end
    end, "EquipmentSets")

    -- Register for PLAYER_ENTERING_WORLD to catch already-loaded addons
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        -- Check if Outfitter is already loaded
        if Outfitter_GetCategoryOrder or gOutfitter_Initialized then
            outfitterReady = true
            HookOutfitterEvents()
            FullScan()
        end

        -- Check if ItemRack is already loaded (stock or fork)
        if IsItemRackLoaded() then
            itemRackReady = true
            FullScan()
        end
    end, "EquipmentSets")

    -- Fallback: on the first gear change after login, if our set data is still
    -- empty but Outfitter / ItemRack is loaded, rescan. Outfitter's own
    -- auto-add-on-swap mutates its outfit list, which normally fires an EDIT
    -- event back to us — but if that event chain misses (e.g. hook not yet
    -- registered the moment Outfitter broadcasts), this gives us a second
    -- chance on the next vanilla PLAYER_EQUIPMENT_CHANGED. Throttled to only
    -- run while data is empty, so it's a no-op during normal play.
    addon.Modules.Events:Register("PLAYER_EQUIPMENT_CHANGED", function()
        if CountSets() > 0 then return end
        if not (outfitterReady or itemRackReady
                or Outfitter_GetCategoryOrder or gOutfitter_Initialized
                or IsItemRackLoaded()) then
            return
        end
        if Outfitter_GetCategoryOrder or gOutfitter_Initialized then
            outfitterReady = true
            HookOutfitterEvents()
        end
        if IsItemRackLoaded() then
            itemRackReady = true
        end
        FullScan()
    end, "EquipmentSets")

    -- Polling frame: keep retrying FullScan until it produces set data (not just
    -- until Outfitter globals exist — Outfitter defines its globals the moment
    -- its Lua loads, but its outfit list isn't populated until later in the load
    -- sequence, so the first scan after a /reload often finds zero sets). Up to
    -- 30 ticks (1s each); stop on first non-empty scan or timeout.
    local initCheckFrame = CreateFrame("Frame")
    initCheckFrame.elapsed = 0
    initCheckFrame.checks = 0
    initCheckFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed < 1 then return end
        this.elapsed = 0
        this.checks = this.checks + 1

        -- Hook Outfitter events the moment globals appear, even if the scan
        -- below is empty — that way Outfitter's own post-load EDIT events
        -- still wake us up once its outfit list actually populates.
        if not outfitterReady and (gOutfitter_Initialized or Outfitter_GetCategoryOrder) then
            outfitterReady = true
            HookOutfitterEvents()
        end
        if not itemRackReady and IsItemRackLoaded() then
            itemRackReady = true
        end

        -- Retry the scan each tick until we produce at least one set, or time out.
        if outfitterReady or itemRackReady then
            local count = FullScan()
            if count > 0 then
                this:Hide()
                return
            end
        end

        -- Give up after 30 seconds. One final scan in case any late-loading
        -- addon registered its data without firing an event we catch.
        if this.checks > 30 then
            this:Hide()
            if Outfitter_GetCategoryOrder or IsItemRackLoaded() then
                FullScan()
            end
        end
    end)
    initCheckFrame:Show()

    -- Initial scan: PLAYER_LOGIN runs after PLAYER_ENTERING_WORLD and any
    -- ADDON_LOADED for addons that loaded before Guda, so the handlers
    -- registered above would miss the initial session for already-loaded
    -- ItemRack/Outfitter. Catch them here.
    if Outfitter_GetCategoryOrder or gOutfitter_Initialized then
        outfitterReady = true
        HookOutfitterEvents()
    end
    if IsItemRackLoaded() then
        itemRackReady = true
    end
    if outfitterReady or itemRackReady then
        FullScan()
    end

    addon:Debug("EquipmentSets: Module initialized")
end

-- Force a rescan of all equipment set sources
function EquipmentSets:Rescan()
    FullScan()
end
