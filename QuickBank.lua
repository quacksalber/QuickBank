-- QuickBank: Initialisierung, Events und Slash-Befehle
-- Eigenes Fenster zum schnellen Verschieben von Items zwischen Inventar und Bank.
-- Die Blizzard-Fenster werden nicht angefasst.

local ADDON, ns = ...

local REFRESH_EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "BANK_TABS_CHANGED",
}

local function InitDB()
    QuickBankDB = QuickBankDB or {}
    if QuickBankDB.autoOpen == nil then QuickBankDB.autoOpen = true end
    QuickBankDB.rules = QuickBankDB.rules or {}
end

local function OnBankOpened()
    ns.state.bankOpen = true
    if QuickBankDB.autoOpen then ns.ShowMain(true) end
    ns.Refresh()
end

local function OnBankClosed()
    ns.state.bankOpen = false
    ns.StopQueue()
    if QuickBankDB.autoOpen then ns.ShowMain(false) end
    ns.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        ns.CreateMainFrame()
        self:RegisterEvent("BANKFRAME_OPENED")
        self:RegisterEvent("BANKFRAME_CLOSED")
        for _, ev in ipairs(REFRESH_EVENTS) do
            pcall(self.RegisterEvent, self, ev) -- nicht jedes Event existiert in jedem Client
        end
    elseif event == "BANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "BANKFRAME_CLOSED" then
        OnBankClosed()
    else
        ns.Refresh()
    end
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

local COMMANDS = {
    auto = function()
        QuickBankDB.autoOpen = not QuickBankDB.autoOpen
        ns.Print("Automatisches Öffnen an der Bank: " .. (QuickBankDB.autoOpen and "an" or "aus"))
    end,
    reset = function()
        QuickBankDB.pos = nil
        ns.ResetMainPosition(nil)
    end,
    regeln = function() ns.ToggleRules() end,
}
COMMANDS.rules = COMMANDS.regeln

SLASH_QUICKBANK1 = "/quickbank"
SLASH_QUICKBANK2 = "/qb"
SlashCmdList.QUICKBANK = function(msg)
    local cmd = COMMANDS[ns.Trim(msg):lower()]
    if cmd then cmd() else ns.ToggleMain() end
end
