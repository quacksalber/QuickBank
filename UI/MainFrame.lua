-- QuickBank: Hauptfenster (Bank links, Inventar rechts)

local _, ns = ...
local W = ns.Widgets

local COLS, SIZE, PAD, HEADER_H = 8, 36, 3, 24
local PANEL_W = COLS * (SIZE + PAD)
local SCROLLBAR_W = 26

local frame, bankPanel, invPanel

---------------------------------------------------------------------------
-- Item-Buttons
---------------------------------------------------------------------------

local function ItemButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then GameTooltip:SetHyperlink(self.link) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-Linksklick oder Rechtsklick: nach " ..
        (self.toBank and "Bank" or "Inventar") .. " verschieben", 0.2, 1, 0.2)
    GameTooltip:Show()
end

local function ItemButton_OnClick(self, button)
    if (button == "LeftButton" and IsShiftKeyDown()) or button == "RightButton" then
        ns.MoveItem(self.bag, self.slot, self.itemID, self.toBank)
    end
end

local function CreateItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", ItemButton_OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", ItemButton_OnClick)
    return b
end

local function SetItem(b, info, toBank)
    b.bag, b.slot, b.itemID, b.link, b.toBank = info.bag, info.slot, info.itemID, info.hyperlink, toBank
    b.icon:SetTexture(info.iconFileID)
    b.icon:SetDesaturated(info.isLocked and true or false)
    b.count:SetText((info.stackCount or 1) > 1 and info.stackCount or "")
    local q = info.quality
    if q and q > 1 and ns.GetQualityColor then
        local r, g, bl = ns.GetQualityColor(q) -- 4. Rückgabewert (Hex-String) nicht als Alpha übergeben
        b.border:SetVertexColor(r, g, bl)
        b.border:Show()
    else
        b.border:Hide()
    end
end

---------------------------------------------------------------------------
-- Kategorie-Kopfzeilen
---------------------------------------------------------------------------

local function CreateHeader(parent, toBank)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(PANEL_W, HEADER_H)

    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(1, 1, 1, 0.06)

    h.text = W.Label(h, nil, "GameFontNormal")
    h.text:SetPoint("LEFT", 4, 0)

    h.btn = W.Button(h, toBank and "Alle >> Bank" or "Alle >> Inventar", 112, 20)
    h.btn:SetPoint("RIGHT", -2, 0)
    h.btn:SetScript("OnClick", function() ns.MoveCategory(h.category, toBank) end)
    return h
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

local function CreatePanel(parent, toBank, x)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", x, -88)
    p:SetPoint("BOTTOM", 0, 34)
    p:SetWidth(PANEL_W + SCROLLBAR_W)
    p.toBank = toBank
    p.isBank = not toBank -- Panel zeigt die Bank, wenn es Richtung Inventar verschiebt
    p.buttons, p.headers = {}, {}

    p.title = W.Label(p, nil, "GameFontHighlightLarge")
    p.title:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 2, 6)

    p.moveHits = W.Button(p, toBank and "Treffer >> Bank" or "Treffer >> Inventar", 130, 20)
    p.moveHits:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", -SCROLLBAR_W, 3)
    p.moveHits:SetScript("OnClick", function() ns.MoveSearchResults(toBank) end)
    p.moveHits:Hide()

    p.scroll, p.content = W.Scroll(p, PANEL_W)
    p.scroll:SetPoint("TOPLEFT")
    p.scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_W, 0)

    p.empty = W.Label(p, nil, "GameFontDisable")
    p.empty:SetPoint("TOP", p.scroll, "TOP", 0, -40)
    return p
end

local function ItemLess(a, b)
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Sammelt die sichtbaren Items, gruppiert und sortiert nach Kategorie
local function CollectGroups(bags)
    local groups, order = {}, {}
    ns.ForEachItem(bags, function(bag, slot, info)
        if not ns.MatchesSearch(info) then return end
        local key = ns.ItemCategory(info.itemID)
        if not groups[key] then
            groups[key] = {}
            order[#order + 1] = key
        end
        info.bag, info.slot = bag, slot
        table.insert(groups[key], info)
    end)
    table.sort(order, ns.CategoryLess)
    for _, key in ipairs(order) do table.sort(groups[key], ItemLess) end
    return groups, order
end

local function UpdatePanel(p)
    local bankOpen = ns.state.bankOpen
    local bags = p.isBank and ns.BankBags() or ns.InventoryBags()
    local visible = not p.isBank or bankOpen

    local groups, order = {}, {}
    if visible then groups, order = CollectGroups(bags) end

    local nBtn, nHdr, y = 0, 0, 0
    for _, key in ipairs(order) do
        local items = groups[key]

        nHdr = nHdr + 1
        local h = p.headers[nHdr] or CreateHeader(p.content, p.toBank)
        p.headers[nHdr] = h
        h.category = key
        h.text:SetText(("%s (%d)"):format(ns.CategoryName(key), #items))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:Show()
        y = y + HEADER_H + PAD

        for i, info in ipairs(items) do
            nBtn = nBtn + 1
            local b = p.buttons[nBtn] or CreateItemButton(p.content)
            p.buttons[nBtn] = b
            SetItem(b, info, p.toBank)
            local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", col * (SIZE + PAD), -(y + row * (SIZE + PAD)))
            b:Show()
        end
        y = y + math.ceil(#items / COLS) * (SIZE + PAD) + 6
    end

    for i = nBtn + 1, #p.buttons do p.buttons[i]:Hide() end
    for i = nHdr + 1, #p.headers do p.headers[i]:Hide() end
    p.content:SetHeight(math.max(y, 1))

    local searching = ns.IsSearching()
    p.moveHits:SetShown(searching and nBtn > 0 and bankOpen)

    local label = p.isBank and "Bank" or "Inventar"
    if not visible then
        p.title:SetText(label)
        p.empty:SetText("Bank ist nicht geöffnet.")
        p.empty:Show()
    else
        p.title:SetText(("%s  |cff999999(%d frei)|r"):format(label, ns.CountFree(bags)))
        p.empty:SetText(searching and "Keine Treffer." or "Leer.")
        p.empty:SetShown(nBtn == 0)
    end
end

---------------------------------------------------------------------------
-- Aktualisierung (gebündelt, damit viele Events nur ein Update auslösen)
---------------------------------------------------------------------------

local refreshPending = false

function ns.Refresh()
    if not frame or not frame:IsShown() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.05, function()
        refreshPending = false
        if frame:IsShown() then
            UpdatePanel(invPanel)
            UpdatePanel(bankPanel)
        end
    end)
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function CreateToolbar(f)
    local searchLabel = W.Label(f, "Suche:")
    searchLabel:SetPoint("TOPLEFT", 18, -36)

    local searchBox = W.Input(f, 220)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetScript("OnTextChanged", function(self) ns.SetSearch(self:GetText()) end)

    local tidyBtn = W.Button(f, "Aufräumen", 100)
    tidyBtn:SetPoint("TOPRIGHT", -16, -30)
    tidyBtn:SetScript("OnClick", ns.RunAllRules)
    W.Tooltip(tidyBtn, "Wendet alle aktiven Regeln an", "ANCHOR_BOTTOM")

    local rulesBtn = W.Button(f, "Regeln", 80)
    rulesBtn:SetPoint("RIGHT", tidyBtn, "LEFT", -4, 0)
    rulesBtn:SetScript("OnClick", function() ns.ToggleRules() end)
end

function ns.CreateMainFrame()
    frame = W.Window("QuickBankFrame", "QuickBank", PANEL_W * 2 + SCROLLBAR_W * 2 + 44, 560)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        QuickBankDB.pos = { point, relPoint, x, y }
    end)
    frame:SetScript("OnShow", ns.Refresh)
    ns.ResetMainPosition(QuickBankDB.pos)

    CreateToolbar(frame)
    bankPanel = CreatePanel(frame, false, 14)
    invPanel = CreatePanel(frame, true, 14 + PANEL_W + SCROLLBAR_W + 16)

    local hint = W.Label(frame,
        "Shift-Linksklick oder Rechtsklick verschiebt ein Item   |   \"Alle >>\" verschiebt die ganze Kategorie",
        "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 12)
end

function ns.ResetMainPosition(pos)
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end
end

function ns.ShowMain(show)
    frame:SetShown(show)
end

function ns.ToggleMain()
    frame:SetShown(not frame:IsShown())
end
