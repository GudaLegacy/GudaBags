-- Guda Money Tracker
-- Tracks player money and saves to database

local addon = Guda

local MoneyTracker = {}
addon.Modules.MoneyTracker = MoneyTracker

local lastMoney = 0

-- Update money in database
function MoneyTracker:Update()
    local currentMoney = GetMoney()

    if currentMoney ~= lastMoney then
        addon.Modules.DB:SaveMoney(currentMoney)
        lastMoney = currentMoney
        addon:Debug("Money updated: %s", addon.Modules.Utils:FormatMoney(currentMoney))
    end
end

-- Get current money
function MoneyTracker:GetCurrentMoney()
    return GetMoney()
end

-- Get total money across all characters (optionally filter by faction and/or realm)
function MoneyTracker:GetTotalMoney(sameFactionOnly, currentRealmOnly)
    return addon.Modules.DB:GetTotalMoney(sameFactionOnly, currentRealmOnly)
end

-- Initialize money tracker
function MoneyTracker:Initialize()
    -- Track money changes and save immediately
    addon.Modules.Events:OnMoneyChanged(function()
        MoneyTracker:Update()
    end, "MoneyTracker")

    -- Initial update and save on login (uses pooled timer)
    addon.Modules.Events:OnPlayerLogin(function()
        Guda_ScheduleTimer(1, function()
            MoneyTracker:Update()
            addon:Debug("Initial money saved")
        end)
    end, "MoneyTracker")
end
