-- Guda Tooltip Module - Lua 5.0 Compatible
local addon = Guda

local Tooltip = {}
addon.Modules.Tooltip = Tooltip

-- Reusable tables to avoid per-mouseover garbage (cleared before each use)
local _characterCounts = {}
local _breakdownParts = {}
local _charParts = {}

--=============================================================================
-- Item Counting Helper Functions (extracted for clarity and reuse)
--=============================================================================

-- Helper function to get item ID from link (Lua 5.0 compatible)
local function GetItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local _, _, itemID = string.find(link, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Count items in saved bag/bank data structure
-- Used for both bags and bank counting from saved character data
local function CountFromSavedContainers(containersData, itemID)
    local count = 0
    if not containersData or type(containersData) ~= "table" then
        return count
    end

    for bagID, bagData in pairs(containersData) do
        if bagData and type(bagData) == "table" and bagData.slots and type(bagData.slots) == "table" then
            for slotID, itemData in pairs(bagData.slots) do
                if itemData and type(itemData) == "table" and itemData.link then
                    local slotItemID = GetItemIDFromLink(itemData.link)
                    if slotItemID == itemID then
                        count = count + (itemData.count or 1)
                    end
                end
            end
        end
    end

    return count
end

-- Count items in saved mailbox data structure
local function CountFromSavedMailbox(mailboxData, itemID)
    local count = 0
    if not mailboxData or type(mailboxData) ~= "table" then
        return count
    end

    for _, mail in ipairs(mailboxData) do
        local itemsToCheck = mail.items or (mail.item and {mail.item}) or {}
        for _, item in ipairs(itemsToCheck) do
            local slotItemID = item.link and GetItemIDFromLink(item.link)
            if slotItemID == itemID then
                count = count + (item.count or 1)
            elseif not slotItemID and item.name then
                -- Fallback to name matching if link is missing
                local targetName = Guda.GetItemInfo("item:" .. itemID .. ":0:0:0")
                if targetName == item.name then
                    count = count + (item.count or 1)
                end
            end
        end
    end

    return count
end

-- Count items in saved equipped data structure
local function CountFromSavedEquipped(equippedData, itemID)
    local count = 0
    if not equippedData or type(equippedData) ~= "table" then
        return count
    end

    for slotName, itemData in pairs(equippedData) do
        if itemData and type(itemData) == "table" and itemData.link then
            local slotItemID = GetItemIDFromLink(itemData.link)
            if slotItemID == itemID then
                count = count + 1
            end
        end
    end

    return count
end

-- Count items in live container (bags or bank)
local function CountFromLiveContainer(bagIDs, itemID)
    local count = 0

    for _, bagID in ipairs(bagIDs) do
        local numSlots = GetContainerNumSlots(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bagID, slot)
                if link then
                    local slotItemID = GetItemIDFromLink(link)
                    if slotItemID == itemID then
                        local _, itemCount = GetContainerItemInfo(bagID, slot)
                        count = count + (itemCount or 1)
                    end
                end
            end
        end
    end

    return count
end

-- Count items in live mailbox
local function CountFromLiveMailbox(itemID)
    local count = 0

    if not (addon.Modules.MailboxScanner and addon.Modules.MailboxScanner:IsMailboxOpen()) then
        return count
    end

    local numInboxItems = GetInboxNumItems()
    for i = 1, numInboxItems do
        local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem then
            local numAttachments = GetInboxNumAttachments and GetInboxNumAttachments(i) or 1
            if numAttachments == 0 and hasItem then
                numAttachments = 1
            end

            for j = 1, numAttachments do
                local name, _, itemCount = GetInboxItem(i, j)
                if name then
                    local itemLink = addon.Modules.Utils:GetInboxItemLink(i, j)
                    if itemLink then
                        local slotItemID = GetItemIDFromLink(itemLink)
                        if slotItemID == itemID then
                            count = count + (itemCount or 1)
                        end
                    end
                end
            end
        end
    end

    return count
end

-- Count items in live equipment slots
local function CountFromLiveEquipped(itemID)
    local count = 0

    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local slotItemID = GetItemIDFromLink(link)
            if slotItemID == itemID then
                count = count + 1
            end
        end
    end

    return count
end

--=============================================================================
-- Main Counting Functions
--=============================================================================

-- Count items for current character using live game data
local function CountCurrentCharacterItems(itemID)
    local bagCount = 0
    local bankCount = 0
    local mailCount = 0
    local equippedCount = 0

    -- Count bags in real-time
    bagCount = CountFromLiveContainer({0, 1, 2, 3, 4, -2}, itemID)

    -- Count bank: live if open, otherwise from saved data
    local bankFrame = getglobal("BankFrame")
    if bankFrame and bankFrame:IsVisible() then
        -- Main bank + bank bags
        bankCount = CountFromLiveContainer({-1, 5, 6, 7, 8, 9, 10, 11}, itemID)
    else
        -- Use saved data
        local playerName = addon.Modules.DB:GetPlayerFullName()
        local charData = Guda_DB and Guda_DB.characters and Guda_DB.characters[playerName]
        if charData then
            bankCount = CountFromSavedContainers(charData.bank, itemID)
        end
    end

    -- Count mailbox: live if open, otherwise from saved data
    if addon.Modules.MailboxScanner and addon.Modules.MailboxScanner:IsMailboxOpen() then
        mailCount = CountFromLiveMailbox(itemID)
    else
        local playerName = addon.Modules.DB:GetPlayerFullName()
        local charData = Guda_DB and Guda_DB.characters and Guda_DB.characters[playerName]
        if charData then
            mailCount = CountFromSavedMailbox(charData.mailbox, itemID)
        end
    end

    -- Count equipped items in real-time
    equippedCount = CountFromLiveEquipped(itemID)

    return bagCount, bankCount, equippedCount, mailCount
end

-- Count items for a specific character (current or other)
local function CountItemsForCharacter(itemID, characterData, isCurrentChar)
    -- For current character, use real-time counting
    if isCurrentChar then
        return CountCurrentCharacterItems(itemID)
    end

    -- For other characters, use saved data
    local bagCount = CountFromSavedContainers(characterData.bags, itemID)
    local bankCount = CountFromSavedContainers(characterData.bank, itemID)
    local mailCount = CountFromSavedMailbox(characterData.mailbox, itemID)
    local equippedCount = CountFromSavedEquipped(characterData.equipped, itemID)

    return bagCount, bankCount, equippedCount, mailCount
end


-- Get class color
local function GetClassColor(classToken)
	if not classToken then return 1.0, 1.0, 1.0 end
	local color = RAID_CLASS_COLORS[classToken]
	if color then return color.r, color.g, color.b end
	return 1.0, 1.0, 1.0
end

function Tooltip:AddInventoryInfo(tooltip, link)
-- Check if the setting is enabled
	if not addon.Modules.DB:GetSetting("showTooltipCounts") then
		return
	end

-- Check if database is properly initialized and has the expected structure
	if not Guda_DB or type(Guda_DB) ~= "table" then
		return
	end

	-- Safely check characters - it might be nil or a string during early initialization
	if not Guda_DB.characters or type(Guda_DB.characters) ~= "table" then
	-- If characters is a string or nil, just return silently
		return
	end

	local itemID = GetItemIDFromLink(link)
	if not itemID then
		return
	end

	local totalBags = 0
	local totalBank = 0
	local totalMail = 0
	local totalEquipped = 0
	local hasAnyItems = false

	-- Reuse module-level tables (clear before use to avoid per-call allocation)
	local characterCounts = _characterCounts
	for k in pairs(characterCounts) do characterCounts[k] = nil end
	local ccIndex = 0

	local currentPlayerName = addon.Modules.DB:GetPlayerFullName()
	local currentRealm = GetRealmName()

	-- Count items across characters on current realm only
	local sources = { { data = Guda_DB.characters, shared = false } }
	if addon.sharedCharacters then
		table.insert(sources, { data = addon.sharedCharacters, shared = true })
	end

	for _, source in ipairs(sources) do
		for charName, charData in pairs(source.data) do
			if type(charData) == "table" and charData.realm == currentRealm and not addon.Modules.DB:IsGoldBlacklisted(charName) then
				local isCurrentChar = (charName == currentPlayerName)
				local bagCount, bankCount, equippedCount, mailCount = CountItemsForCharacter(itemID, charData, isCurrentChar)

				if bagCount > 0 or bankCount > 0 or equippedCount > 0 or mailCount > 0 then
					hasAnyItems = true
					totalBags = totalBags + bagCount
					totalBank = totalBank + bankCount
					totalMail = totalMail + mailCount
					totalEquipped = totalEquipped + equippedCount
					ccIndex = ccIndex + 1
					if not characterCounts[ccIndex] then
						characterCounts[ccIndex] = {}
					end
					local entry = characterCounts[ccIndex]
					entry.name = charData.name or charName
					entry.classToken = charData.classToken
					entry.bagCount = bagCount
					entry.bankCount = bankCount
					entry.mailCount = mailCount
					entry.equippedCount = equippedCount
					entry.isCurrent = isCurrentChar
					entry.isShared = source.shared
				end
			end
		end
	end
	-- Clean up any stale entries beyond current count
	for i = ccIndex + 1, table.getn(characterCounts) do
		characterCounts[i] = nil
	end

	local totalCount = totalBags + totalBank + totalMail + totalEquipped

	if hasAnyItems then

		-- Top padding above the Inventory block (~10-12px visually)
		tooltip:AddLine(" ")

		-- Inventory label in exact bag frame title color
		tooltip:AddLine("|cFFFFD200" .. Guda_L["Inventory"] .. "|r")

		-- Total line with cyan label and white count (reuse module-level table)
		local totalText = "|cFF00FFFF" .. Guda_L["Total"] .. "|r: |cFFFFFFFF" .. totalCount .. "|r"
		local breakdownParts = _breakdownParts
		local bpIndex = 0
		if totalBags > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Bags"] .. "|r: |cFFFFFFFF" .. totalBags .. "|r" end
		if totalBank > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Bank"] .. "|r: |cFFFFFFFF" .. totalBank .. "|r" end
		if totalMail > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Mail"] .. "|r: |cFFFFFFFF" .. totalMail .. "|r" end
		if totalEquipped > 0 then bpIndex = bpIndex + 1; breakdownParts[bpIndex] = "|cFF00FFFF" .. Guda_L["Equipped"] .. "|r: |cFFFFFFFF" .. totalEquipped .. "|r" end
		for i = bpIndex + 1, table.getn(breakdownParts) do breakdownParts[i] = nil end

		local breakdownText = ""
		if bpIndex > 0 then
			breakdownText = "(" .. table.concat(breakdownParts, " | ") .. ")"
		end
		tooltip:AddDoubleLine(totalText, breakdownText, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)

		-- Sort: own chars first (current char at top), then shared
		table.sort(characterCounts, function(a, b)
			if a.isShared ~= b.isShared then return not a.isShared end
			if a.isCurrent and not b.isCurrent then return true end
			if not a.isCurrent and b.isCurrent then return false end
			return a.name < b.name
		end)

		-- Reuse module-level parts table for per-character breakdown
		local parts = _charParts
		local sharedSeparatorShown = false
		for _, charInfo in ipairs(characterCounts) do
			if charInfo.isShared and not sharedSeparatorShown then
				tooltip:AddLine("|cFF80C0FF" .. Guda_L["Other Accounts"] .. "|r")
				sharedSeparatorShown = true
			end
			local r, g, b = GetClassColor(charInfo.classToken)
			local pIndex = 0

			if charInfo.bagCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. Guda_L["Bags"] .. "|r: |cFFFFFFFF" .. charInfo.bagCount .. "|r"
			end
			if charInfo.bankCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. Guda_L["Bank"] .. "|r: |cFFFFFFFF" .. charInfo.bankCount .. "|r"
			end
			if charInfo.mailCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. Guda_L["Mail"] .. "|r: |cFFFFFFFF" .. charInfo.mailCount .. "|r"
			end
			if charInfo.equippedCount > 0 then
				pIndex = pIndex + 1; parts[pIndex] = "|cFF00FFFF" .. Guda_L["Equipped"] .. "|r: |cFFFFFFFF" .. charInfo.equippedCount .. "|r"
			end
			for i = pIndex + 1, table.getn(parts) do parts[i] = nil end

			local countText = ""
			if pIndex > 0 then
				countText = table.concat(parts, " | ")
			end

			-- Mark current character
			local displayName = charInfo.name
			if charInfo.isCurrent then
				displayName = displayName .. " |cFFFFFF00(*)|r"
			end

			tooltip:AddDoubleLine(displayName, countText, r, g, b, 1.0, 1.0, 1.0)
		end

		-- Recompute layout to fit the lines we just added.
		tooltip:Show()
	end
end

function Tooltip:Initialize()
	addon:Print("Initializing tooltip module...")

	-- Post-hook strategy: hooksecurefunc runs AFTER Blizzard's own setter, so we
	-- never replace the original method, never touch global SetTooltipMoney, and
	-- never break Blizzard's call chain. The Inventory block lands at the bottom
	-- of the tooltip (after the vendor sell-price line, when one is present),
	-- matching upstream GudaBags' tooltip ordering.

	-- Hook a tooltip setter and inject the inventory block via the supplied
	-- link-getter. Skips silently if the method is absent on this client
	-- (e.g. SetCraftItem was removed in patch 3.0.2 — the Crafts UI was
	-- folded into TradeSkill — so it doesn't exist on 3.3.5a). AddInventoryInfo
	-- handles its own :Show() once it's actually appended lines.
	local function HookLink(target, method, getLink)
		if not target or not target[method] then return end
		hooksecurefunc(target, method, function(self, ...)
			local link = getLink(...)
			if link then
				Tooltip:AddInventoryInfo(self, link)
			end
		end)
	end

	HookLink(GameTooltip, "SetBagItem", function(bag, slot)
		local link = GetContainerItemLink(bag, slot)
		if link then return link end
		-- Bank main bag (-1) reports through inventory slots, not container slots
		local bankFrame = getglobal("BankFrame")
		if bag == -1 and bankFrame and bankFrame:IsVisible() then
			local invSlot = BankButtonIDToInvSlotID(slot)
			if invSlot then return GetInventoryItemLink("player", invSlot) end
		end
	end)

	HookLink(GameTooltip, "SetHyperlink", function(link)
		if not link then return end
		-- Some callers pass the visible "|H...|h" form; extract the inner item link.
		local _, _, inner = string.find(link, "|H(.+)|h")
		local itemLink = inner or link
		if strfind(itemLink, "item:") then return itemLink end
	end)

	HookLink(GameTooltip, "SetInventoryItem", function(unit, slot)
		return GetInventoryItemLink(unit, slot)
	end)

	HookLink(GameTooltip, "SetLootItem", function(slot)
		return GetLootSlotLink(slot)
	end)

	HookLink(GameTooltip, "SetQuestItem", function(itemType, index)
		return GetQuestItemLink(itemType, index)
	end)

	HookLink(GameTooltip, "SetMerchantItem", function(index)
		return GetMerchantItemLink(index)
	end)

	HookLink(GameTooltip, "SetAuctionItem", function(auctionType, index)
		return GetAuctionItemLink(auctionType, index)
	end)

	HookLink(GameTooltip, "SetInboxItem", function(index, itemIndex)
		return addon.Modules.Utils and addon.Modules.Utils:GetInboxItemLink(index, itemIndex)
	end)

	HookLink(GameTooltip, "SetTradeSkillItem", function(skillIndex, reagentIndex)
		if reagentIndex then return GetTradeSkillReagentItemLink(skillIndex, reagentIndex) end
		return GetTradeSkillItemLink(skillIndex)
	end)

	HookLink(GameTooltip, "SetCraftItem", function(skillIndex, reagentIndex)
		if reagentIndex then return GetCraftReagentItemLink(skillIndex, reagentIndex) end
		return GetCraftItemLink(skillIndex)
	end)

	HookLink(ItemRefTooltip, "SetHyperlink", function(link)
		if link and strfind(link, "item:") then return link end
	end)

	-- Clear cache function
	function Tooltip:ClearCache()
		addon:Debug("Tooltip cache cleared")
	end

	-- Clear cache on bag updates (debounced to prevent lag on rapid updates)
	local frame = CreateFrame("Frame")
	local cacheClearPending = false
	frame:RegisterEvent("BAG_UPDATE")
	frame:SetScript("OnEvent", function()
		if event == "BAG_UPDATE" then
			-- Skip tooltip cache clearing while sorting (items don't change, just move)
			if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then return end
			if cacheClearPending then return end
			cacheClearPending = true
			-- Debounce: batch rapid BAG_UPDATE events (uses pooled timer)
			Guda_ScheduleTimer(0.2, function()
				cacheClearPending = false
				Tooltip:ClearCache()
			end)
		end
	end)

	addon:Print("Tooltip integration enabled")
end