-- Guda Quest Items Database
-- Contains item IDs that are quest items for specific factions
-- Used to mark items as quest items even when tooltip doesn't indicate it

local addon = Guda

-- Quest items by faction
-- "both" = quest item for Alliance and Horde
-- "alliance" = quest item for Alliance only
-- "horde" = quest item for Horde only
addon.QuestItemsDB = {
    both = {
        [3404] = true,
        [8483] = true,
        [8393] = true,
        [8396] = true,
        [11404] = true,
        [20404] = true,
    },
    alliance = {
        [723] = true,
        [729] = true,
        [730] = true,
        [731] = true,
        [2296] = true,
    },
    horde = {
        --[2296] = true,
    },
}

-- Check if an item ID is a quest item for the given faction
-- Returns: isQuestItem (boolean), factionSpecific (string or nil)
function addon:IsQuestItemByID(itemID, playerFaction)
    if not itemID then return false, nil end

    -- Check "both" factions first
    if self.QuestItemsDB.both[itemID] then
        return true, "both"
    end

    -- Check faction-specific
    if playerFaction then
        local factionKey = string.lower(playerFaction)
        if self.QuestItemsDB[factionKey] and self.QuestItemsDB[factionKey][itemID] then
            return true, factionKey
        end
    end

    return false, nil
end
