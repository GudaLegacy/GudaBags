-- Guda Quest Item Bar
-- Displays usable quest items in a separate bar

local addon = Guda
local QuestItemBar = addon.Modules.QuestItemBar
if not QuestItemBar then
    -- Fallback if Init.lua changed
    QuestItemBar = {}
    addon.Modules.QuestItemBar = QuestItemBar
end

local buttons = {}
local questItems = {}
local flyoutButtons = {}
local flyoutFrame

--=====================================================
-- Quest border (yellow) for quest item bar buttons
--=====================================================
local QUEST_BORDER_PADDING = 1

local function GetOrCreateQuestBorder(button)
    if button._questBorder then return button._questBorder end

    local qStyle = "rounded"
    if addon.Modules and addon.Modules.Theme then
        qStyle = addon.Modules.Theme:GetQualityBorderStyle()
    end

    local frame = CreateFrame("Frame", nil, button)
    frame:SetFrameLevel(button:GetFrameLevel() + 3)
    local pad = QUEST_BORDER_PADDING
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, pad)
    frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -pad)
    if qStyle == "square" then
        frame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = -1, right = -1, top = -1, bottom = -1 },
        })
    else
        frame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
    end
    frame:SetBackdropBorderColor(1, 1, 0, 1) -- yellow
    frame:Hide()
    button._questBorder = frame
    return frame
end

local function ShowQuestBorder(button)
    local frame = GetOrCreateQuestBorder(button)
    frame:SetBackdropBorderColor(1, 1, 0, 1)
    frame:Show()
end

local function HideQuestBorder(button)
    if button._questBorder then
        button._questBorder:Hide()
    end
end

--=====================================================
-- Quest Item Detection (using centralized ItemDetection)
--=====================================================

-- Combined function to check if an item is a quest item AND usable
-- Uses centralized ItemDetection module for consistent detection
function QuestItemBar:CheckQuestItemUsable(bagID, slotID)
    if not bagID or not slotID then return false, false, false end

    -- Get item data for ItemDetection
    local itemData = nil
    if addon.Modules.BagScanner then
        itemData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)
    end

    -- Use centralized ItemDetection
    if addon.Modules.ItemDetection and itemData then
        local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)
        return props.isQuestItem, props.isQuestStarter, props.isQuestUsable
    end

    -- Fallback to Utils if ItemDetection not available
    if addon.Modules.Utils and addon.Modules.Utils.IsQuestItem then
        local isQuestItem, isQuestStarter = addon.Modules.Utils:IsQuestItem(bagID, slotID, nil, false, false)
        -- For usability fallback, check if it's a quest item (assume usable)
        return isQuestItem, isQuestStarter, isQuestItem
    end

    return false, false, false
end

-- Scan bags for quest items (optimized: single tooltip scan per item)
function QuestItemBar:ScanForQuestItems()
    questItems = {}

    -- Scan backpack and 4 bags
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                -- Single combined check instead of two separate tooltip scans
                local isQuest, isStarter, isUsable = self:CheckQuestItemUsable(bagID, slotID)
                if isQuest and isUsable and not isStarter then
                    table.insert(questItems, {
                        bagID = bagID,
                        slotID = slotID,
                        texture = texture,
                        count = count
                    })
                end
            end
        end
    end
end

-- Legacy function kept for compatibility (now calls combined function)
function QuestItemBar:IsQuestItem(bagID, slotID)
    local isQuestItem, isQuestStarter, _ = self:CheckQuestItemUsable(bagID, slotID)
    return isQuestItem, isQuestStarter
end

function QuestItemBar:PinItem(itemID, slot)
    if not itemID then return end
    local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    
    local targetSlot = slot or 1
    if not slot then
        -- Original logic: Find first empty slot or replace first
        for i = 1, 2 do
            if pins[i] == itemID then return end
        end
        
        for i = 1, 2 do
            if not pins[i] then
                targetSlot = i
                break
            end
        end
    end
    
    pins[targetSlot] = itemID
    addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
    self:Update()
    return true
end

-- Create a single quest-bar slot button. Extracted from the Update loop so
-- the same button-construction code path is reachable from Initialize
-- (pre-warm, out of combat) and Update (fallback if a slot is ever missing).
-- Returns nil if called during combat (CreateFrame on the secure template
-- is forbidden).
function QuestItemBar:CreateSlotButton(parent, i)
    if not parent then return nil end
    if buttons[i] then return buttons[i] end
    if InCombatLockdown and InCombatLockdown() then return nil end

    -- SecureActionButtonTemplate lets the engine dispatch item-use through a
    -- secure path (type="item" / "item" attribute). Without it, a tainted
    -- SetScript("OnClick", ...) calling UseContainerItem on a consumable
    -- quest item triggers the Ascension 3.3.5a "GudaBags has been blocked
    -- from an action only available to the Blizzard UI" popup.
    local button = CreateFrame(
        "Button",
        "Guda_QuestItemBarButton" .. i,
        parent,
        "Guda_ItemButtonTemplate, SecureActionButtonTemplate"
    )
    button:SetAttribute("type", "item")
    buttons[i] = button

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() end)
    button:SetScript("OnReceiveDrag", function() end)
    -- OnMouseDown handles two intercepts before the secure OnClick:
    --   * Alt+Right-Click: unpin this slot (must suppress so the secure
    --     dispatcher doesn't ALSO use the item on the now-unpinned slot)
    --   * Shift+Left-Click: start moving the bar
    -- Default left/right-click without modifiers falls through to the
    -- secure dispatcher (type="item") and uses the item.
    button:SetScript("OnMouseDown", function()
        if arg1 == "RightButton" and IsAltKeyDown() then
            local slot = this.slotIndex
            if slot then
                local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
                pins[slot] = nil
                addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
                QuestItemBar:Update()
            end
            if Guda_SuppressNextClick then
                Guda_SuppressNextClick(this)
            end
            return
        end
        if arg1 == "LeftButton" then
            local p = this:GetParent()
            if p and IsShiftKeyDown() and not p.isMoving and not (CursorHasItem and CursorHasItem()) then
                p:StartMoving()
                p.isMoving = true
            end
        end
    end)
    button:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" then
            local p = this:GetParent()
            if p and p.isMoving then
                p:StopMovingOrSizing()
                p.isMoving = false
                local point, _, relativePoint, x, y = p:GetPoint()
                if point then
                    addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
                end
            end
        end
    end)

    button.slotIndex = i
    button:Hide()
    return button
end

-- Pre-warm both quest-bar slot buttons at Initialize (out of combat) so
-- Update never has to CreateFrame a secure template during combat.
function QuestItemBar:PreCreateButtons()
    local frame = Guda_QuestItemBar
    if not frame then return end
    self:CreateSlotButton(frame, 1)
    self:CreateSlotButton(frame, 2)
end

-- Update the bar buttons.
-- Every button is a SecureActionButton; in combat, Show/Hide/SetAttribute/
-- SetPoint on them is forbidden. Skip the refresh during combat and re-run
-- on PLAYER_REGEN_ENABLED — the bar stays in its pre-combat state until
-- combat ends.
function QuestItemBar:Update()
    local showQuestBar = addon.Modules.DB:GetSetting("showQuestBar")
    local frame = Guda_QuestItemBar

    if not frame then return end

    if InCombatLockdown and InCombatLockdown() then
        self._deferredUpdate = true
        return
    end

    if showQuestBar == false then
        frame:Hide()
        return
    end

    self:ScanForQuestItems()
    
    -- If no quest items found, hide the bar
    if table.getn(questItems or {}) == 0 then
        frame:Hide()
        return
    end

    frame:Show()

    local pinnedItems = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    local buttonSize = addon.Modules.DB:GetSetting("questBarSize") or 36
    local spacing = 2
    local xOffset = 5

    -- Update frame height based on button size
    frame:SetHeight(buttonSize + 8)
    
    -- Used to keep track of which bag items are already displayed
    local usedBagSlots = {}

    local slots = math.min(2, table.getn(questItems or {}))
    for i = 1, slots do
        local index = i
        local button = buttons[i]
        if not button then
            -- Fallback: first Update ever ran while PreCreateButtons hadn't
            -- run yet. Out of combat this still works; in combat it will
            -- fail silently since CreateFrame on a secure template is
            -- blocked. Initialize should always call PreCreateButtons first.
            button = QuestItemBar:CreateSlotButton(frame, i)
        end
        if not button then
            -- Creation failed (combat lockdown) — skip this slot this Update.
            break
        end

        -- Track which slot this button represents so the OnMouseDown closure
        -- can unpin the correct index regardless of which button was originally
        -- created for which slot.
        button.slotIndex = i

        local itemToDisplay = nil
        
        -- 1. Try to find the pinned item for this slot
        local pinnedID = pinnedItems[i]
        if pinnedID then
            -- Find this item in bags
            for _, item in ipairs(questItems) do
                local itemID = addon.Modules.Utils:ExtractItemID(GetContainerItemLink(item.bagID, item.slotID))
                if itemID == pinnedID and not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end
        
        -- 2. If no pinned item or pinned item not found, auto-fill
        if not itemToDisplay then
            for _, item in ipairs(questItems) do
                if not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end

        if itemToDisplay then
            button.bagID = itemToDisplay.bagID
            button.slotID = itemToDisplay.slotID
            button.hasItem = true
            button.fromDB = itemToDisplay.fromDB
            
            local link = itemToDisplay.link
            if not link and itemToDisplay.bagID and itemToDisplay.slotID then
                link = GetContainerItemLink(itemToDisplay.bagID, itemToDisplay.slotID)
            end
            button.itemData = { link = link }
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            icon:SetTexture(itemToDisplay.texture)
            icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            
            local countText = getglobal(button:GetName() .. "Count")
            if itemToDisplay.count > 1 then
                countText:SetText(itemToDisplay.count)
                countText:Show()
            else
                countText:Hide()
            end
            
            -- Point the secure dispatcher at this quest item's link so clicks
            -- use THIS specific stack. Attribute mutation is forbidden during
            -- combat; skip the update and let the previous value ride. Alt+
            -- Right unpin is handled in OnMouseDown above with suppression.
            if link and not (InCombatLockdown and InCombatLockdown()) then
                button:SetAttribute("item", link)
            end

            ShowQuestBorder(button)
            button:Show()
        else
            -- Empty slot
            HideQuestBorder(button)
            button.hasItem = false
            button.bagID = nil
            button.slotID = nil
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            local slotStyle = "rounded"
            if addon.Modules and addon.Modules.Theme then
                slotStyle = addon.Modules.Theme:GetSlotStyle()
            end
            if slotStyle == "square" then
                icon:SetTexture("Interface\\Buttons\\WHITE8x8")
                icon:SetVertexColor(0.05, 0.05, 0.05, 0.5)
            else
                icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                icon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            end
            
            local countText = getglobal(button:GetName() .. "Count")
            countText:Hide()

            -- Empty slot: clear the secure "item" attribute so any click
            -- (including keybind) becomes a no-op via the secure dispatcher.
            -- Alt+Right unpin is handled in OnMouseDown for this case too.
            if not (InCombatLockdown and InCombatLockdown()) then
                button:SetAttribute("item", nil)
            end

            button:Show()
        end

        button:SetScript("OnEnter", function()
            if this.hasItem then
                Guda_ItemButton_OnEnter(this)
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText("Quest Slot " .. index)
                GameTooltip:AddLine("Auto-fills with usable quest items.", 1, 1, 1)
                GameTooltip:AddLine("Alt-Click an item in bags to pin it.", 0, 1, 0)
                GameTooltip:AddLine("Alt-Right-Click to unpin.", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
            
            -- Only show flyout if there are more quest items to show
            if QuestItemBar:HasExtraQuestItems() then
                QuestItemBar:ShowFlyout(this)
            end
        end)

        button:SetScript("OnLeave", function()
            if this.hasItem then
                Guda_ItemButton_OnLeave(this)
            else
                GameTooltip:Hide()
            end
            QuestItemBar:HideFlyout()
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
        local slotStyle = "rounded"
        if addon.Modules and addon.Modules.Theme then
            slotStyle = addon.Modules.Theme:GetSlotStyle()
        end

        local normalTex = getglobal(button:GetName() .. "NormalTexture")
        if slotStyle == "square" then
            -- Hide rounded border in pfUI mode
            button:SetNormalTexture("")
            if normalTex then
                normalTex:SetTexture(nil)
                normalTex:Hide()
            end
            -- Crop icon for pfUI style
            if icon then
                icon:SetTexCoord(.08, .92, .08, .92)
            end
        else
            local borderSize = buttonSize * 64 / 37
            if normalTex then
                normalTex:SetWidth(borderSize)
                normalTex:SetHeight(borderSize)
            end
        end

        -- Resize empty slot background
        local emptyBg = getglobal(button:GetName() .. "_EmptySlotBg")
        if emptyBg then
            if slotStyle == "square" then
                emptyBg:SetTexture("Interface\\Buttons\\WHITE8x8")
                emptyBg:SetVertexColor(0.05, 0.05, 0.05, 1)
                emptyBg:ClearAllPoints()
                emptyBg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                emptyBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            else
                emptyBg:SetWidth(buttonSize)
                emptyBg:SetHeight(buttonSize)
            end
        end

        -- Update visual overlays (cooldown, etc)
        if Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(button)
        end
    end

    -- Hide any extra buttons beyond current slots
    for j = slots + 1, table.getn(buttons) do
        local extra = buttons[j]
        if extra then
            extra:Hide()
            extra.hasItem = false
        end
    end

    -- Fixed width for current number of slots
    local newWidth = xOffset * 2 + slots * (buttonSize + spacing) - spacing
    frame:SetWidth(newWidth)

    -- (Re)wire the key bindings to the secure buttons now that they exist.
    self:WireKeybindings()
end

function QuestItemBar:UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button:IsShown() and Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(button)
        end
    end
    for _, button in ipairs(flyoutButtons) do
        if button:IsShown() and Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(button)
        end
    end
end

-- Check if there are more quest items than shown in the main slots
function QuestItemBar:HasExtraQuestItems()
    local mainItemIDs = {}
    for i = 1, 2 do
        local btn = buttons[i]
        if btn and btn.hasItem and btn.itemData and btn.itemData.link then
            local id = addon.Modules.Utils:ExtractItemID(btn.itemData.link)
            if id then mainItemIDs[id] = true end
        end
    end
    
    for _, item in ipairs(questItems or {}) do
        local link = item.link
        if not link and item.bagID and item.slotID then
            link = GetContainerItemLink(item.bagID, item.slotID)
        end
        
        if link then
            local id = addon.Modules.Utils:ExtractItemID(link)
            if id and not mainItemIDs[id] then
                return true
            end
        end
    end
    
    return false
end

function QuestItemBar:ShowFlyout(parent)
    if not flyoutFrame then return end
    
    self:UpdateFlyout(parent)
    flyoutFrame:Show()
end

function QuestItemBar:HideFlyout(immediate)
    if not flyoutFrame then return end
    
    if immediate then
        flyoutFrame:Hide()
        flyoutFrame:SetScript("OnUpdate", nil)
        return
    end
    
    -- Delay hiding to allow moving mouse to the flyout
    flyoutFrame.hideTime = GetTime() + 0.1
    flyoutFrame:SetScript("OnUpdate", function()
        if GetTime() > this.hideTime then
            if not MouseIsOver(this) and (not this.parent or not MouseIsOver(this.parent)) then
                this:Hide()
            end
            this:SetScript("OnUpdate", nil)
        end
    end)
end

function QuestItemBar:UpdateFlyout(parent)
    if not flyoutFrame then return end
    flyoutFrame.parent = parent

    local buttonSize = addon.Modules.DB:GetSetting("questBarSize") or 36
    local spacing = 2
    
    -- Collect items not in main buttons
    local displayItems = {}
    local mainItemIDs = {}
    for _, btn in ipairs(buttons) do
        if btn and btn.hasItem and btn.itemData and btn.itemData.link then
            local id = addon.Modules.Utils:ExtractItemID(btn.itemData.link)
            if id then mainItemIDs[id] = true end
        end
    end
    
    for _, item in ipairs(questItems) do
        local link = GetContainerItemLink(item.bagID, item.slotID)
        local id = addon.Modules.Utils:ExtractItemID(link)
        if id and not mainItemIDs[id] then
            -- Avoid duplicates in flyout if multiple stacks exist (optional, but TrinketMenu does it)
            local alreadyInFlyout = false
            for _, existing in ipairs(displayItems) do
                if existing.itemID == id then
                    alreadyInFlyout = true
                    break
                end
            end
            
            if not alreadyInFlyout then
                table.insert(displayItems, {
                    bagID = item.bagID,
                    slotID = item.slotID,
                    texture = item.texture,
                    count = item.count,
                    itemID = id,
                    link = link
                })
            end
        end
    end
    
    -- Hide all flyout buttons first
    for _, btn in ipairs(flyoutButtons) do
        btn:Hide()
    end
    
    if table.getn(displayItems) == 0 then
        flyoutFrame:Hide()
        return
    end
    
    -- Position flyout above the parent button
    flyoutFrame:ClearAllPoints()
    flyoutFrame:SetPoint("BOTTOM", parent, "TOP", 0, 5)
    
    for i, item in ipairs(displayItems) do
        local btn = flyoutButtons[i]
        if not btn then
            btn = CreateFrame("Button", "Guda_QuestItemFlyoutButton" .. i, flyoutFrame, "Guda_ItemButtonTemplate")
            table.insert(flyoutButtons, btn)
            
            btn:SetScript("OnDragStart", function() end)
            btn:SetScript("OnReceiveDrag", function() end)
            btn:SetScript("OnMouseDown", function() end)
            
            btn:SetScript("OnEnter", function()
                Guda_ItemButton_OnEnter(this)
                if flyoutFrame then flyoutFrame.hideTime = GetTime() + 5 end -- Keep open
            end)
            btn:SetScript("OnLeave", function()
                Guda_ItemButton_OnLeave(this)
                QuestItemBar:HideFlyout()
            end)
        end
        
        btn.bagID = item.bagID
        btn.slotID = item.slotID
        btn.hasItem = true
        btn.fromDB = item.fromDB
        btn.itemData = { link = item.link }
        btn.itemID = item.itemID
        
        local icon = getglobal(btn:GetName() .. "IconTexture")
        icon:SetTexture(item.texture)
        
        local countText = getglobal(btn:GetName() .. "Count")
        if item.count > 1 then
            countText:SetText(item.count)
            countText:Show()
        else
            countText:Hide()
        end
        
        btn:SetScript("OnClick", function()
            if this.fromDB then
                addon:Print(Guda_L["Item is not currently in your bags (loading from database)."])
                return
            end
            
            local targetSlot = 1
            if flyoutFrame.parent then
                -- Check if parent is Guda_QuestItemBarButton2
                if flyoutFrame.parent:GetName() == "Guda_QuestItemBarButton2" then
                    targetSlot = 2
                end
            end
            
            if arg1 == "LeftButton" then
                QuestItemBar:PinItem(this.itemID, targetSlot)
            elseif arg1 == "RightButton" then
                -- Both clicks now work on targetSlot based on context, 
                -- but we'll keep RightButton for slot 2 as a fallback/original behavior 
                -- or just make it also use targetSlot if we want "both clicks work on mouse 1".
                -- The requirement says "make both clicks work on mouse 1 instead of mouse 2 and mouse 1 clicks to separate bars"
                -- This phrasing is a bit ambiguous, but contextually it means 
                -- Mouse 1 on flyout button should replace the bar that was hovered.
                QuestItemBar:PinItem(this.itemID, targetSlot)
            end
            QuestItemBar:HideFlyout(true)
        end)
        
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", flyoutFrame, "BOTTOM", 0, (i-1) * (buttonSize + spacing) + 5)
        btn:SetWidth(buttonSize)
        btn:SetHeight(buttonSize)

        -- Resize all button textures to match button size
        local btnIcon = getglobal(btn:GetName() .. "IconTexture")
        if btnIcon then
            btnIcon:SetWidth(buttonSize)
            btnIcon:SetHeight(buttonSize)
        end

        -- Scale or hide border based on theme
        local btnNormalTex = getglobal(btn:GetName() .. "NormalTexture")
        local flyoutSlotStyle = "rounded"
        if addon.Modules and addon.Modules.Theme then
            flyoutSlotStyle = addon.Modules.Theme:GetSlotStyle()
        end
        if flyoutSlotStyle == "square" then
            btn:SetNormalTexture("")
            if btnNormalTex then
                btnNormalTex:SetTexture(nil)
                btnNormalTex:Hide()
            end
            if btnIcon then
                btnIcon:SetTexCoord(.08, .92, .08, .92)
            end
        else
            local borderSize = buttonSize * 64 / 37
            if btnNormalTex then
                btnNormalTex:SetWidth(borderSize)
                btnNormalTex:SetHeight(borderSize)
            end
        end

        -- Resize empty slot background
        local btnEmptyBg = getglobal(btn:GetName() .. "_EmptySlotBg")
        if btnEmptyBg then
            btnEmptyBg:SetWidth(buttonSize)
            btnEmptyBg:SetHeight(buttonSize)
        end

        btn:Show()

        if Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(btn)
        end
    end
    
    flyoutFrame:SetWidth(buttonSize + 10)
    flyoutFrame:SetHeight(table.getn(displayItems) * (buttonSize + spacing) + 10)
end

-- Wire the GUDA_USE_QUEST_ITEM_{1,2} bindings to simulate a hardware click on
-- the corresponding secure quest-bar button. Pressing the key dispatches
-- through the secure type="item" path — no addon-taint, no blocked-action
-- popup on consumable quest items. SetBindingClick is forbidden during
-- combat, so skip and try again on the next out-of-combat Update.
function QuestItemBar:WireKeybindings()
    if not SetBindingClick then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if getglobal("Guda_QuestItemBarButton1") then
        SetBindingClick("GUDA_USE_QUEST_ITEM_1", "Guda_QuestItemBarButton1", "LeftButton")
    end
    if getglobal("Guda_QuestItemBarButton2") then
        SetBindingClick("GUDA_USE_QUEST_ITEM_2", "Guda_QuestItemBarButton2", "LeftButton")
    end
end

function QuestItemBar:Initialize()
    local frame = CreateFrame("Frame", "Guda_QuestItemBar", UIParent)
    frame:SetWidth(40)
    frame:SetHeight(45)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    --addon:ApplyBackdrop(frame, "DEFAULT_FRAME")
    
    -- Create flyout frame
    flyoutFrame = CreateFrame("Frame", "Guda_QuestItemFlyout", UIParent)
    flyoutFrame:SetFrameStrata("TOOLTIP")
    flyoutFrame:Hide()
    addon:ApplyBackdrop(flyoutFrame, "DEFAULT_FRAME")
    
    -- Handle dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" and IsShiftKeyDown() and not this.isMoving then
            this:StartMoving()
            this.isMoving = true
        end
    end)
    frame:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" and this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            local point, _, relativePoint, x, y = this:GetPoint()
            if point then
                addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
            end
        end
    end)
    
    -- Restore position
    local pos = addon.Modules.DB:GetSetting("questBarPosition")
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
            QuestItemBar:Update()
        end)
    end, "QuestItemBar")

    addon.Modules.Events:Register("BAG_UPDATE_COOLDOWN", function()
        QuestItemBar:UpdateCooldowns()
    end, "QuestItemBar")
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        QuestItemBar:Update()
    end, "QuestItemBar")

    -- Re-run any refresh deferred while the player was in combat.
    addon.Modules.Events:Register("PLAYER_REGEN_ENABLED", function()
        if QuestItemBar._deferredUpdate then
            QuestItemBar._deferredUpdate = false
            QuestItemBar:Update()
        end
    end, "QuestItemBar")

    -- Rule 3 (RULES.md): pre-create both secure slot buttons out of combat.
    -- Without this, if the player first acquires a quest item mid-combat,
    -- Update would try to CreateFrame a secure template during lockdown and
    -- silently fail.
    QuestItemBar:PreCreateButtons()

    QuestItemBar:Update()
    addon:Debug("QuestItemBar initialized")
end

-- Debug function to diagnose QuestItemBar issues
-- Usage: /script Guda.Modules.QuestItemBar:Debug()
function QuestItemBar:Debug()
    addon:Print("=== QuestItemBar Debug ===")

    -- Check setting
    local showQuestBar = addon.Modules.DB:GetSetting("showQuestBar")
    addon:Print("showQuestBar setting: " .. tostring(showQuestBar))

    -- Check frame
    local frame = Guda_QuestItemBar
    addon:Print("Frame exists: " .. tostring(frame ~= nil))
    if frame then
        addon:Print("Frame shown: " .. tostring(frame:IsShown()))
    end

    -- Scan all bags for potential quest items
    addon:Print("--- Scanning bags ---")
    local foundCount = 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                local itemLink = GetContainerItemLink(bagID, slotID)
                local itemData = addon.Modules.BagScanner:ScanSlot(bagID, slotID)

                if itemData then
                    local props = addon.Modules.ItemDetection:GetItemProperties(itemData, bagID, slotID)

                    -- Show items that are quest-related OR have Quest class
                    if props.isQuestItem or props.isQuestUsable or (itemData.class and itemData.class == "Quest") then
                        foundCount = foundCount + 1
                        addon:Print(string.format("[%d:%d] %s", bagID, slotID, itemData.name or "Unknown"))
                        addon:Print(string.format("  class=%s, isQuest=%s, isUsable=%s, isStarter=%s",
                            tostring(itemData.class),
                            tostring(props.isQuestItem),
                            tostring(props.isQuestUsable),
                            tostring(props.isQuestStarter)))

                        -- Check if it would show in bar
                        local wouldShow = props.isQuestItem and props.isQuestUsable and not props.isQuestStarter
                        addon:Print("  Would show in bar: " .. tostring(wouldShow))
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        addon:Print("No quest-related items found in bags")
    end

    addon:Print("=== End Debug ===")
end

QuestItemBar.isLoaded = true
