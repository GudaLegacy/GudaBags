-- Guda Tracked Item Bar
-- Displays tracked items with their total bag count

local addon = Guda
local TrackedItemBar = addon.Modules.TrackedItemBar
if not TrackedItemBar then
    TrackedItemBar = {}
    addon.Modules.TrackedItemBar = TrackedItemBar
end

local buttons = {}
local trackedItemsInfo = {}

-- Check if an item is a quest item by scanning tooltip
local function IsQuestItem(bagID, slotID)
    if addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        return addon.Modules.Utils:IsQuestItem(bagID, slotID, nil, false, false)
    end
    return false, false
end

-- Scan bags for tracked items and calculate total counts
function TrackedItemBar:ScanForTrackedItems()
    trackedItemsInfo = {}
    local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}

    local itemCounts = {}
    local itemTextures = {}
    local itemLinks = {}
    local itemOrder = {}
    local itemIsQuest = {}
    local itemIsQuestStarter = {}

    -- Scan backpack and 4 bags
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                local link = GetContainerItemLink(bagID, slotID)
                local id = addon.Modules.Utils:ExtractItemID(link)
                if id and trackedIDs[id] then
                    if not itemCounts[id] then
                        itemCounts[id] = 0
                        itemTextures[id] = texture
                        itemLinks[id] = link
                        itemCounts[id .. "_bag"] = bagID
                        itemCounts[id .. "_slot"] = slotID
                        -- Check if quest item
                        local isQuest, isStarter = IsQuestItem(bagID, slotID)
                        itemIsQuest[id] = isQuest
                        itemIsQuestStarter[id] = isStarter
                        table.insert(itemOrder, id)
                    end
                    itemCounts[id] = itemCounts[id] + count
                end
            end
        end
    end

    for _, id in ipairs(itemOrder) do
        local bagID = itemCounts[id .. "_bag"]
        local slotID = itemCounts[id .. "_slot"]
        local link = itemLinks[id]

        -- Detect unusable and junk status using centralized ItemDetection
        local isUnusable = false
        local isJunk = false
        if addon.Modules.ItemDetection and link then
            local itemData = { link = link }
            local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
            isUnusable = props.isUnusable
            isJunk = props.isJunk
        end

        table.insert(trackedItemsInfo, {
            itemID = id,
            texture = itemTextures[id],
            count = itemCounts[id],
            link = link,
            bagID = bagID,
            slotID = slotID,
            isQuest = itemIsQuest[id],
            isQuestStarter = itemIsQuestStarter[id],
            isUnusable = isUnusable,
            isJunk = isJunk,
        })
    end
end

-- Create a single tracked-bar slot button. Extracted from the Update loop so
-- the same construction code path is reachable from Initialize (pre-warm,
-- out of combat) and from Update (fallback if a slot is missing). Returns
-- nil if called during combat (CreateFrame on the secure template is
-- forbidden).
function TrackedItemBar:CreateSlotButton(parent, i)
    if not parent then return nil end
    if buttons[i] then return buttons[i] end
    if InCombatLockdown and InCombatLockdown() then return nil end

    -- SecureActionButtonTemplate lets the engine dispatch item-use through a
    -- secure path (type="item" / "item" attribute).
    local button = CreateFrame(
        "Button",
        "Guda_TrackedItemBarButton" .. i,
        parent,
        "Guda_ItemButtonTemplate, SecureActionButtonTemplate"
    )
    button:SetAttribute("type", "item")
    buttons[i] = button

    -- Quest border (golden)
    local questBorder = CreateFrame("Frame", nil, button)
    questBorder:SetFrameLevel(button:GetFrameLevel() + 6)
    questBorder:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    questBorder:SetBackdropBorderColor(1.0, 0.82, 0, 1)
    questBorder:Hide()
    button.questBorder = questBorder

    -- Quest icon (question mark in corner)
    local questIcon = CreateFrame("Frame", nil, button)
    questIcon:SetFrameLevel(button:GetFrameLevel() + 7)
    questIcon:SetWidth(16)
    questIcon:SetHeight(16)
    local iconTex = questIcon:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints(questIcon)
    iconTex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    iconTex:SetTexCoord(0, 1, 0, 1)
    questIcon:Hide()
    button.questIcon = questIcon

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() end)
    button:SetScript("OnReceiveDrag", function() end)

    -- PreClick gates the secure type="item" dispatcher BEFORE it fires.
    -- If any modifier is held (Shift for drag, Alt for untrack, Ctrl reserved)
    -- we clear `type` so the dispatcher is a no-op for this click; PostClick
    -- restores `type="item"` so subsequent plain clicks still use the item.
    -- This is the mechanism the original GudaBags uses (see RULES.md Rule 0),
    -- and the reason the earlier `Guda_SuppressNextClick` approach didn't
    -- work: RegisterForClicks only gates Lua OnClick delivery, not the
    -- SecureActionButton engine dispatch which reads `type` + hardware event
    -- directly.
    button:SetScript("PreClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        if IsShiftKeyDown() or IsAltKeyDown() or IsControlKeyDown() then
            this:SetAttribute("type", nil)
        else
            this:SetAttribute("type", "item")
        end
    end)
    button:SetScript("PostClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        this:SetAttribute("type", "item")
    end)

    -- OnMouseDown still runs the drag + untrack side effects. PreClick
    -- above blocks the secure item-use so we do NOT need to call
    -- Guda_SuppressNextClick here anymore.
    button:SetScript("OnMouseDown", function()
        if arg1 ~= "LeftButton" then return end

        if IsAltKeyDown() and this.itemID then
            local trackedIDs = addon.Modules.DB:GetSetting("trackedItems") or {}
            trackedIDs[this.itemID] = nil
            addon.Modules.DB:SetSetting("trackedItems", trackedIDs)
            if Guda.Modules.BagFrame and Guda.Modules.BagFrame.Update then
                Guda.Modules.BagFrame:Update()
            end
            TrackedItemBar:Update()
            return
        end

        if IsShiftKeyDown() and not (CursorHasItem and CursorHasItem()) then
            this:GetParent():StartMoving()
            this:GetParent().isMoving = true
        end
    end)
    button:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" then
            local p = this:GetParent()
            if p.isMoving then
                p:StopMovingOrSizing()
                p.isMoving = false
                local point, _, relativePoint, x, y = p:GetPoint()
                addon.Modules.DB:SetSetting("trackedBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
            end
        end
    end)

    button:Hide()
    return button
end

-- Pre-warm a reasonable slot count at Initialize (out of combat). If the
-- player tracks more items than this after combat starts, extras will be
-- missing until combat ends — but that edge case doesn't break the addon.
local TRACKED_BAR_PREWARM = 10
function TrackedItemBar:PreCreateButtons()
    local frame = Guda_TrackedItemBar
    if not frame then return end
    for i = 1, TRACKED_BAR_PREWARM do
        self:CreateSlotButton(frame, i)
    end
end

-- Update the bar buttons.
-- Every button is a SecureActionButton; in combat, Show/Hide/SetAttribute/
-- SetPoint on them is forbidden. Skip the whole refresh during combat and
-- re-run it on PLAYER_REGEN_ENABLED. The bar simply stays in its pre-combat
-- state until combat ends.
function TrackedItemBar:Update()
    local frame = Guda_TrackedItemBar

    if not frame then return end

    if InCombatLockdown and InCombatLockdown() then
        -- Flag a deferred refresh; PLAYER_REGEN_ENABLED picks it up.
        self._deferredUpdate = true
        return
    end

    frame:Show()

    self:ScanForTrackedItems()

    local buttonSize = addon.Modules.DB:GetSetting("trackedBarSize") or 36
    local spacing = 2
    local xOffset = 5

    -- Update frame height based on button size
    frame:SetHeight(buttonSize + 8)
    
    -- Hide all buttons and their overlays initially
    for _, btn in ipairs(buttons) do
        btn:Hide()
        if btn.unusableOverlay then btn.unusableOverlay:Hide() end
        if btn.junkIcon then btn.junkIcon:Hide() end
    end

    for i, info in ipairs(trackedItemsInfo) do
        local button = buttons[i]
        if not button then
            -- Fallback: pre-warm didn't cover this slot. Out of combat it
            -- will succeed; in combat CreateFrame on the secure template is
            -- blocked, and we break out of the Update loop.
            button = TrackedItemBar:CreateSlotButton(frame, i)
        end
        if not button then
            break
        end

        button.hasItem = true
        button.itemData = { link = info.link }
        button.itemID = info.itemID
        button.bagID = info.bagID
        button.slotID = info.slotID
        button.isReadOnly = false -- Changed to false to allow interaction and tooltips showing usage
        
        local icon = getglobal(button:GetName() .. "IconTexture")
        icon:SetTexture(info.texture)
        icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        
        local countText = getglobal(button:GetName() .. "Count")
        countText:SetText(info.count)
        countText:Show()
        
        -- Point the secure dispatcher at the current tracked item's link so
        -- clicks use THIS specific stack (not just any item with the same
        -- name). Attribute mutation is forbidden during combat; if the item
        -- changes mid-fight we keep the previous value and refresh on the
        -- next Update out of combat. Alt+Left untrack is handled in
        -- OnMouseDown above with click suppression.
        if not (InCombatLockdown and InCombatLockdown()) then
            button:SetAttribute("item", info.link)
        end

        button:SetScript("OnEnter", function()
            Guda_ItemButton_OnEnter(this)
        end)

        button:SetScript("OnLeave", function()
            Guda_ItemButton_OnLeave(this)
        end)

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i-1) * (buttonSize + spacing), 0)
        button:SetWidth(buttonSize)
        button:SetHeight(buttonSize)

        -- Resize all button textures to match button size
        local icon = getglobal(button:GetName() .. "IconTexture")
        if icon then
            icon:SetWidth(buttonSize)
            icon:SetHeight(buttonSize)
        end

        -- Scale border proportionally (64/37 is the standard ratio for WoW item buttons)
        local borderSize = buttonSize * 64 / 37
        local normalTex = getglobal(button:GetName() .. "NormalTexture")
        if normalTex then
            normalTex:SetWidth(borderSize)
            normalTex:SetHeight(borderSize)
        end

        -- Resize empty slot background
        local emptyBg = getglobal(button:GetName() .. "_EmptySlotBg")
        if emptyBg then
            emptyBg:SetWidth(buttonSize)
            emptyBg:SetHeight(buttonSize)
        end

        -- Position and show/hide quest border
        if button.questBorder then
            button.questBorder:ClearAllPoints()
            button.questBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            button.questBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            if info.isQuest then
                button.questBorder:Show()
            else
                button.questBorder:Hide()
            end
        end

        -- Position and show/hide quest icon
        if button.questIcon then
            local questIconSize = math.max(12, math.min(20, buttonSize * 0.35))
            button.questIcon:SetWidth(questIconSize)
            button.questIcon:SetHeight(questIconSize)
            button.questIcon:ClearAllPoints()
            button.questIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 0)

            if info.isQuest then
                -- Set appropriate texture based on quest type
                local tex = button.questIcon:GetRegions()
                if tex and tex.SetTexture then
                    if info.isQuestStarter then
                        tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                    else
                        tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
                    end
                end
                button.questIcon:Show()
            else
                button.questIcon:Hide()
            end
        end

        -- Apply unusable red overlay (same as bag slot indicator)
        if info.isUnusable then
            if not button.unusableOverlay then
                local overlay = button:CreateTexture(nil, "OVERLAY")
                overlay:SetAllPoints(icon)
                overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                overlay:Hide()
                button.unusableOverlay = overlay
            end
            local r, g, b = 0.9, 0.2, 0.2
            if RED_FONT_COLOR then
                r, g, b = RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b
            end
            button.unusableOverlay:SetVertexColor(r, g, b, 0.45)
            button.unusableOverlay:Show()
        else
            if button.unusableOverlay then
                button.unusableOverlay:Hide()
            end
        end

        -- Apply junk vendor icon (same as bag slot indicator)
        if info.isJunk then
            if not button.junkIcon then
                local junkFrame = CreateFrame("Frame", nil, button)
                junkFrame:SetFrameStrata("HIGH")
                local junkTex = junkFrame:CreateTexture(nil, "OVERLAY")
                junkTex:SetAllPoints(junkFrame)
                junkTex:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
                junkTex:SetTexCoord(0, 1, 0, 1)
                junkFrame.texture = junkTex
                button.junkIcon = junkFrame
            end
            local junkIconSize = math.max(10, math.min(14, buttonSize * 0.30))
            button.junkIcon:SetWidth(junkIconSize)
            button.junkIcon:SetHeight(junkIconSize)
            button.junkIcon:ClearAllPoints()
            button.junkIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            button.junkIcon:Show()
        else
            if button.junkIcon then
                button.junkIcon:Hide()
            end
        end

        button:Show()
    end

    local numItems = table.getn(trackedItemsInfo)
    if numItems > 0 then
        local newWidth = xOffset * 2 + numItems * (buttonSize + spacing) - spacing
        frame:SetWidth(newWidth)
        frame:Show()
    else
        frame:Hide()
    end
end

function TrackedItemBar:Initialize()
    local frame = CreateFrame("Frame", "Guda_TrackedItemBar", UIParent)
    frame:SetWidth(40)
    frame:SetHeight(45)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200) -- Default above quest bar
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    --addon:ApplyBackdrop(frame, "DEFAULT_FRAME")
    
    -- Handle dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            if IsShiftKeyDown() and not (CursorHasItem and CursorHasItem()) then
                this:StartMoving()
                this.isMoving = true
            end
        end
    end)
    frame:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" and this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            local point, _, relativePoint, x, y = this:GetPoint()
            addon.Modules.DB:SetSetting("trackedBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
        end
    end)
    
    -- Restore position
    local pos = addon.Modules.DB:GetSetting("trackedBarPosition")
    if pos and pos.point then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
    end
    
    -- Register for events with debouncing to prevent lag on rapid bag updates
    local bagUpdatePending = false
    addon.Modules.Events:Register("BAG_UPDATE", function()
        -- Skip updates while sorting is in progress (sort completion will trigger update)
        if addon.Modules.SortEngine and addon.Modules.SortEngine.sortingInProgress then return end
        if bagUpdatePending then return end
        bagUpdatePending = true
        -- Debounce: wait 0.15 seconds before updating (uses pooled timer)
        Guda_ScheduleTimer(0.15, function()
            bagUpdatePending = false
            TrackedItemBar:Update()
        end)
    end, "TrackedItemBar")
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        TrackedItemBar:Update()
    end, "TrackedItemBar")

    addon.Modules.Events:Register("PLAYER_LEVEL_UP", function()
        -- Delay to let client update internal player level before re-scanning tooltips
        Guda_ScheduleTimer(0.5, function()
            if addon.Modules.ItemDetection then
                addon.Modules.ItemDetection:ClearCache()
            end
            TrackedItemBar:Update()
        end)
    end, "TrackedItemBar")

    -- Run the deferred refresh skipped during combat.
    addon.Modules.Events:Register("PLAYER_REGEN_ENABLED", function()
        if TrackedItemBar._deferredUpdate then
            TrackedItemBar._deferredUpdate = false
            TrackedItemBar:Update()
        end
    end, "TrackedItemBar")

    -- Rule 3 (RULES.md): pre-create secure slot buttons out of combat so
    -- Update never has to CreateFrame a secure template under lockdown.
    TrackedItemBar:PreCreateButtons()

    TrackedItemBar:Update()
    addon:Debug("TrackedItemBar initialized")
end

TrackedItemBar.isLoaded = true
