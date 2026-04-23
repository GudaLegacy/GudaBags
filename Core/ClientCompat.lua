-- Guda ClientCompat
-- Detects the running client and normalizes version-specific APIs so the rest
-- of the addon can target one canonical field order for GetItemInfo.
--
-- Supported: 1.12.1 (Vanilla / TurtleWoW) and 3.3.5a (WotLK / Ascension Epoch).

local addon = Guda

-- ---------------------------------------------------------------------------
-- Client detection
-- ---------------------------------------------------------------------------
-- GetBuildInfo signature:
--   1.12.x pristine : (version, build, date)          — 3 returns
--   TurtleWoW 1.12  : (version, build, date, toc?)    — may or may not include toc
--   3.3.5a          : (version, build, date, toc)     — toc == 30300
local _, _, _, tocVersion = GetBuildInfo()
local toc = tonumber(tocVersion) or 0

addon.CLIENT = {
    TOC        = toc,
    IS_VANILLA = (toc == 0) or (toc < 20000),
    IS_TBC     = toc >= 20000 and toc < 30000,
    IS_WOTLK   = toc >= 30000 and toc < 40000,
}

-- ---------------------------------------------------------------------------
-- GetItemInfo normalization
-- ---------------------------------------------------------------------------
-- Canonical order the addon is written against (matches WotLK 3.3.5a native):
--   1  name
--   2  link
--   3  rarity
--   4  level
--   5  minLevel          (on Vanilla this slot holds localized itemCategory;
--                         Guda code typically ignores pos 5 or uses itemType,
--                         so we let the value through unchanged)
--   6  itemType
--   7  subType
--   8  stackCount
--   9  equipLoc
--   10 texture
--   11 sellPrice
--
-- Vanilla 1.12 / TurtleWoW native order differs at positions 7, 8, 9, 10:
--   1-6 identical (treating pos-5 difference as a harmless semantic shift)
--   7  stackCount (vs subType on modern)
--   8  subType    (vs stackCount on modern)
--   9  texture    (vs equipLoc on modern)
--   10 equipLoc   (vs texture on modern)
--   11 sellPrice  (same)
local rawGetItemInfo = GetItemInfo

local function reorder_vanilla_to_modern(name, link, rarity, level, cat, itemType, stackCount, subType, texture, equipLoc, sellPrice)
    if not name then return nil end
    return name, link, rarity, level, cat, itemType, subType, stackCount, equipLoc, texture, sellPrice
end

if addon.CLIENT.IS_VANILLA then
    function addon.GetItemInfo(arg)
        if arg == nil then return nil end
        return reorder_vanilla_to_modern(rawGetItemInfo(arg))
    end
else
    function addon.GetItemInfo(arg)
        if arg == nil then return nil end
        return rawGetItemInfo(arg)
    end
end

-- ---------------------------------------------------------------------------
-- Bank slot counts (used by Constants.lua)
-- ---------------------------------------------------------------------------
-- Vanilla Blizzard 1.12 : 6 bank bags (5..10), 24 main slots.
-- TurtleWoW 1.12        : 7 bank bags (5..11), 24 main slots.
-- WotLK 3.3.5a          : 7 bank bags (5..11), 28 main slots.
function addon.GetBankBagCount()
    local n = tonumber(NUM_BANKBAGSLOTS)
    if n and n > 0 then return n end
    return 6
end

function addon.GetBankMainSlotCount()
    local n = tonumber(NUM_BANKGENERIC_SLOTS)
    if n and n > 0 then return n end
    return 24
end

addon:Debug("ClientCompat loaded (toc=%s, wotlk=%s, vanilla=%s, bankBags=%s, bankMain=%s)",
    tostring(toc),
    tostring(addon.CLIENT.IS_WOTLK),
    tostring(addon.CLIENT.IS_VANILLA),
    tostring(addon.GetBankBagCount()),
    tostring(addon.GetBankMainSlotCount()))
