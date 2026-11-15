-- QuickBank: eigenes Fenster zum schnellen Verschieben von Items
-- zwischen Inventar und Bank. Die Blizzard-Fenster werden nicht angefasst.

local ADDON = ...
local C = C_Container

local COLS, SIZE, PAD, HEADER_H = 8, 36, 3, 24
local PANEL_W = COLS * (SIZE + PAD)
local PREFIX = "|cff33ff99QuickBank|r: "

local bankOpen = false
local frame, invPanel, bankPanel, rulesFrame
local Refresh
local searchText = ""

local function Print(msg) print(PREFIX .. msg) end

---------------------------------------------------------------------------
-- Container-Hilfsfunktionen
---------------------------------------------------------------------------

local function AddIfUsable(list, seen, bag)
    if bag and not seen[bag] and (C.GetContainerNumSlots(bag) or 0) > 0 then
        seen[bag] = true
        list[#list + 1] = bag
    end
end

local function InventoryBags()
    local list, seen = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do AddIfUsable(list, seen, bag) end
    if Enum.BagIndex and Enum.BagIndex.ReagentBag then
        AddIfUsable(list, seen, Enum.BagIndex.ReagentBag)
    end
    return list
end

local function BankBags()
    local list, seen = {}, {}
    -- Modernes Bank-System (Bank-Tabs)
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum.BankType then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do AddIfUsable(list, seen, id) end
        end
    end
    -- Fallback: feste Indizes (Tabs bzw. klassische Bank + Banktaschen)
    if #list == 0 and Enum.BagIndex then
        local B = Enum.BagIndex
        AddIfUsable(list, seen, B.Bank)
        for i = 1, 7 do AddIfUsable(list, seen, B["BankBag_" .. i]) end
        for i = 1, 6 do AddIfUsable(list, seen, B["CharacterBankTab_" .. i]) end
    end
    return list
end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetFullInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
local GetQualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local TRADEGOODS = (Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local MAT_BASE = 100000 -- Gruppenschlüssel für Materialien: MAT_BASE + subclassID

-- Material-Unterklasse -> herstellender Beruf (SkillLine-ID, englischer Fallback-Name)
local MAT_PROFESSION = {
    [1]  = { 202, "Engineering" },     -- Teile
    [4]  = { 755, "Jewelcrafting" },   -- Juwelierskunst
    [5]  = { 197, "Tailoring" },       -- Stoff
    [6]  = { 165, "Leatherworking" },  -- Leder
    [7]  = { 164, "Blacksmithing" },   -- Metall & Stein
    [8]  = { 185, "Cooking" },         -- Kochen
    [9]  = { 171, "Alchemy" },         -- Kräuter
    [12] = { 333, "Enchanting" },      -- Verzauberkunst
    [16] = { 773, "Inscription" },     -- Inschriftenkunde
}

local nameCache = {}

local function ProfessionName(entry)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, entry[1])
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return entry[2]
end

-- Liefert den Gruppenschlüssel eines Items (Itemklasse bzw. Material-Untergruppe)
local function ItemClass(itemID)
    local _, _, _, _, _, classID, subClassID = GetInstant(itemID)
    if classID == TRADEGOODS then return MAT_BASE + (subClassID or 0) end
    return classID or -1
end

local function ClassName(key)
    if nameCache[key] then return nameCache[key] end
    local name
    if key >= MAT_BASE then
        local sub = key - MAT_BASE
        local subName = GetSubClassInfo and GetSubClassInfo(TRADEGOODS, sub)
        local entry = MAT_PROFESSION[sub]
        if entry then
            local prof = ProfessionName(entry)
            name = (subName and subName ~= prof) and (prof .. " (" .. subName .. ")") or prof
        else
            local matName = (GetClassInfo and GetClassInfo(TRADEGOODS)) or "Material"
            name = subName and (matName .. ": " .. subName) or matName
        end
    else
        name = key >= 0 and GetClassInfo and GetClassInfo(key)
    end
    name = name or OTHER or "Sonstiges"
    nameCache[key] = name
    return name
end

-- Normale Kategorien zuerst, Material-Gruppen (nach Beruf) gesammelt danach
local function GroupLess(a, b)
    local am, bm = a >= MAT_BASE, b >= MAT_BASE
    if am ~= bm then return bm end
    return ClassName(a) < ClassName(b)
end

-- Alle auswählbaren Item-Typen (für die Regeln)
local typeList
local function AllTypeKeys()
    if typeList then return typeList end
    typeList = {}
    local seen = {}
    local function add(key)
        if not seen[key] then
            seen[key] = true
            typeList[#typeList + 1] = key
        end
    end
    if Enum.ItemClass then
        for enumName, id in pairs(Enum.ItemClass) do
            if id ~= TRADEGOODS and not enumName:find("Obsolete")
                and GetClassInfo and GetClassInfo(id) then
                add(id)
            end
        end
    else
        for id = 0, 19 do
            if id ~= TRADEGOODS and GetClassInfo and GetClassInfo(id) then add(id) end
        end
    end
    for sub = 0, 19 do
        if GetSubClassInfo and GetSubClassInfo(TRADEGOODS, sub) then add(MAT_BASE + sub) end
    end
    table.sort(typeList, GroupLess)
    return typeList
end

local function CountFree(bags)
    local n = 0
    for _, bag in ipairs(bags) do
        local free, family = C.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then n = n + (free or 0) end
    end
    return n
end

local function MaxStack(itemID)
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local s = C_Item.GetItemMaxStackSizeByID(itemID)
        if s then return s end
    end
    local s = GetFullInfo and select(8, GetFullInfo(itemID))
    return s or 1
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

local function MatchesSearch(info)
    if searchText == "" then return true end
    local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
    return name ~= nil and name:lower():find(searchText, 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Verschiebe-Warteschlange (ein Item nach dem anderen, wartet auf den Server)
---------------------------------------------------------------------------

local queue, queued, reserved, badBags, badSlots = {}, {}, {}, {}, {}
local current, ticker

local function Key(bag, slot) return bag .. ":" .. slot end

local function StopQueue()
    wipe(queue)
    wipe(queued)
    current = nil
    if ticker then ticker:Cancel(); ticker = nil end
end

local function Push(job, front)
    queued[Key(job.bag, job.slot)] = true
    if front then table.insert(queue, 1, job) else queue[#queue + 1] = job end
end

local function Pop()
    local job = table.remove(queue, 1)
    if job then queued[Key(job.bag, job.slot)] = nil end
    return job
end

-- Ziel suchen: zuerst einen Teilstapel desselben Items auffüllen, sonst einen freien Slot.
-- Rückgabe: bag, slot, room (room = Platz im Teilstapel, nil bei freiem Slot)
local function FindTarget(toBank, itemID)
    local now = GetTime()
    local bags = toBank and BankBags() or InventoryBags()

    local max = MaxStack(itemID)
    if max > 1 then
        for _, bag in ipairs(bags) do
            if not badBags[bag] then
                for slot = 1, C.GetContainerNumSlots(bag) do
                    local k = Key(bag, slot)
                    local info = C.GetContainerItemInfo(bag, slot)
                    if info and info.itemID == itemID and not info.isLocked
                        and (info.stackCount or 1) < max
                        and not badSlots[k] and not (reserved[k] and reserved[k] > now) then
                        return bag, slot, max - (info.stackCount or 1)
                    end
                end
            end
        end
    end

    for _, bag in ipairs(bags) do
        local free, family = C.GetContainerNumFreeSlots(bag)
        if not badBags[bag] and (family or 0) == 0 and (free or 0) > 0 then
            for slot = 1, C.GetContainerNumSlots(bag) do
                local k = Key(bag, slot)
                if not C.GetContainerItemInfo(bag, slot) and not (reserved[k] and reserved[k] > now) then
                    return bag, slot
                end
            end
        end
    end
end

local function Step()
    if not bankOpen then StopQueue() return end

    if current then
        local info = C.GetContainerItemInfo(current.bag, current.slot)
        local same = info and info.itemID == current.itemID
        if same and (info.isLocked or info.stackCount == current.count) and GetTime() < current.deadline then
            return -- Server hat den letzten Zug noch nicht bestätigt
        end
        local done = current
        current = nil
        reserved[done.dest] = nil
        -- Nur ein Teil passte in den Ziel-Stapel: Rest erneut einreihen
        if same and done.partial and (info.stackCount or 0) < done.count then
            Push(done, true)
        end
    end

    local job = Pop()
    if not job then StopQueue() return end

    local info = C.GetContainerItemInfo(job.bag, job.slot)
    if not info or info.itemID ~= job.itemID then return end
    if info.isLocked then
        job.tries = (job.tries or 0) + 1
        if job.tries < 40 then
            Push(job)
        else
            Print(("%s ist gesperrt und wurde übersprungen."):format(info.hyperlink or "Item"))
        end
        return
    end

    if GetCursorInfo() then
        Print("Abgebrochen: es liegt etwas auf dem Cursor.")
        StopQueue()
        return
    end

    local dBag, dSlot, room = FindTarget(job.toBank, job.itemID)
    if not dBag then
        Print(job.toBank and "Die Bank ist voll." or "Das Inventar ist voll.")
        StopQueue()
        return
    end

    local count = info.stackCount or 1
    local partial = room and room < count
    if partial then
        C.SplitContainerItem(job.bag, job.slot, room)
    else
        C.PickupContainerItem(job.bag, job.slot)
    end
    C.PickupContainerItem(dBag, dSlot)

    if GetCursorInfo() then
        -- Ziel hat das Item nicht angenommen: Slot bzw. Behälter überspringen
        ClearCursor()
        if room then badSlots[Key(dBag, dSlot)] = true else badBags[dBag] = true end
        Push(job, true)
        return
    end

    job.dest = Key(dBag, dSlot)
    reserved[job.dest] = GetTime() + 2
    job.count = count
    job.partial = partial
    job.deadline = GetTime() + 2
    current = job
end

local function Enqueue(bag, slot, itemID, toBank)
    if not bankOpen then return false end
    if queued[Key(bag, slot)] then return false end
    if not ticker then
        wipe(badBags)
        wipe(badSlots)
        wipe(reserved)
        ticker = C_Timer.NewTicker(0.05, Step)
    end
    Push({ bag = bag, slot = slot, itemID = itemID, toBank = toBank })
    return true
end

local function RequireBank()
    if bankOpen then return true end
    Print("Die Bank muss geöffnet sein.")
    return false
end

-- Reiht alle Items der Quellseite ein, auf die pred(info) zutrifft. Liefert die Anzahl.
local function MoveWhere(toBank, pred)
    local n = 0
    for _, bag in ipairs(toBank and InventoryBags() or BankBags()) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID and pred(info) and Enqueue(bag, slot, info.itemID, toBank) then
                n = n + 1
            end
        end
    end
    return n
end

local function Report(n, what, toBank)
    if n > 0 then
        Print(("%dx %s >> %s"):format(n, what, toBank and "Bank" or "Inventar"))
    end
end

local function MoveCategory(classID, toBank)
    if not RequireBank() then return end
    local n = MoveWhere(toBank, function(info)
        return ItemClass(info.itemID) == classID and MatchesSearch(info)
    end)
    Report(n, ClassName(classID), toBank)
end

local function MoveSearchResults(toBank)
    if not RequireBank() then return end
    Report(MoveWhere(toBank, MatchesSearch), ('"%s"'):format(searchText), toBank)
end

---------------------------------------------------------------------------
-- Regeln
---------------------------------------------------------------------------

local function RunRules(list)
    if not RequireBank() then return end
    local total = 0
    for _, rule in ipairs(list) do
        if rule.enabled ~= false and rule.types and next(rule.types) then
            local n = MoveWhere(rule.toBank, function(info)
                return rule.types[ItemClass(info.itemID)]
            end)
            Report(n, rule.name, rule.toBank)
            total = total + n
        end
    end
    if total == 0 then Print("Regeln: nichts zu verschieben.") end
end

---------------------------------------------------------------------------
-- UI-Bausteine
---------------------------------------------------------------------------

local function CreateCheck(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    return cb
end

local function CreateButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    return b
end

local function CreateInput(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

local function CreateScroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

---------------------------------------------------------------------------
-- Hauptfenster
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
        if RequireBank() then Enqueue(self.bag, self.slot, self.itemID, self.toBank) end
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

local function CreateHeader(parent, toBank)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(PANEL_W, HEADER_H)

    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(1, 1, 1, 0.06)

    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.text:SetPoint("LEFT", 4, 0)

    h.btn = CreateButton(h, toBank and "Alle >> Bank" or "Alle >> Inventar", 112)
    h.btn:SetHeight(20)
    h.btn:SetPoint("RIGHT", -2, 0)
    h.btn:SetScript("OnClick", function() MoveCategory(h.classID, toBank) end)
    return h
end

local function CreatePanel(parent, toBank, x)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", x, -88)
    p:SetPoint("BOTTOM", 0, 34)
    p:SetWidth(PANEL_W + 26)
    p.toBank = toBank
    p.buttons, p.headers = {}, {}

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.title:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 2, 6)

    p.moveHits = CreateButton(p, toBank and "Treffer >> Bank" or "Treffer >> Inventar", 130)
    p.moveHits:SetHeight(20)
    p.moveHits:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", -26, 3)
    p.moveHits:SetScript("OnClick", function() MoveSearchResults(toBank) end)
    p.moveHits:Hide()

    p.scroll, p.content = CreateScroll(p, PANEL_W)
    p.scroll:SetPoint("TOPLEFT")
    p.scroll:SetPoint("BOTTOMRIGHT", -26, 0)

    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    p.empty:SetPoint("TOP", p.scroll, "TOP", 0, -40)
    return p
end

local function UpdatePanel(p)
    local toBank = p.toBank
    local isBankSide = not toBank
    local bags = isBankSide and BankBags() or InventoryBags()
    local label = isBankSide and "Bank" or "Inventar"

    local groups, order = {}, {}
    if not isBankSide or bankOpen then
        for _, bag in ipairs(bags) do
            for slot = 1, C.GetContainerNumSlots(bag) do
                local info = C.GetContainerItemInfo(bag, slot)
                if info and info.itemID and MatchesSearch(info) then
                    local classID = ItemClass(info.itemID)
                    if not groups[classID] then
                        groups[classID] = {}
                        order[#order + 1] = classID
                    end
                    info.bag, info.slot = bag, slot
                    table.insert(groups[classID], info)
                end
            end
        end
    end
    table.sort(order, GroupLess)

    local nBtn, nHdr, y = 0, 0, 0
    for _, classID in ipairs(order) do
        local items = groups[classID]
        table.sort(items, function(a, b)
            if a.itemID ~= b.itemID then return a.itemID < b.itemID end
            if a.bag ~= b.bag then return a.bag < b.bag end
            return a.slot < b.slot
        end)

        nHdr = nHdr + 1
        local h = p.headers[nHdr] or CreateHeader(p.content, toBank)
        p.headers[nHdr] = h
        h.classID = classID
        h.text:SetText(("%s (%d)"):format(ClassName(classID), #items))
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:Show()
        y = y + HEADER_H + PAD

        for i, info in ipairs(items) do
            nBtn = nBtn + 1
            local b = p.buttons[nBtn] or CreateItemButton(p.content)
            p.buttons[nBtn] = b
            b.bag, b.slot, b.itemID, b.link, b.toBank = info.bag, info.slot, info.itemID, info.hyperlink, toBank
            b.icon:SetTexture(info.iconFileID)
            b.icon:SetDesaturated(info.isLocked and true or false)
            b.count:SetText((info.stackCount or 1) > 1 and info.stackCount or "")
            local q = info.quality
            if q and q > 1 and GetQualityColor then
                local r, g, bl = GetQualityColor(q)
                b.border:SetVertexColor(r, g, bl)
                b.border:Show()
            else
                b.border:Hide()
            end
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

    p.moveHits:SetShown(searchText ~= "" and nBtn > 0 and bankOpen)

    if isBankSide and not bankOpen then
        p.title:SetText(label)
        p.empty:SetText("Bank ist nicht geöffnet.")
        p.empty:Show()
    else
        p.title:SetText(("%s  |cff999999(%d frei)|r"):format(label, CountFree(bags)))
        p.empty:SetText(searchText ~= "" and "Keine Treffer." or "Leer.")
        p.empty:SetShown(nBtn == 0)
    end
end

local refreshPending = false
function Refresh()
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
-- Regel-Fenster
---------------------------------------------------------------------------

local RULE_ROW_H, TYPE_ROW_H = 22, 22

local function CreateRulesUI()
    local f = CreateFrame("Frame", "QuickBankRulesFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(580, 480)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER")

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("QuickBank - Regeln")

    local editIndex -- Index der bearbeiteten Regel, nil = neue Regel
    local RefreshList, LoadEditor

    -- Linke Seite: Regelliste -------------------------------------------
    local listLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", 16, -34)
    listLabel:SetText("Regeln")

    local listScroll, listContent = CreateScroll(f, 190)
    listScroll:SetPoint("TOPLEFT", 12, -54)
    listScroll:SetSize(190, 370)
    local rows = {}

    local newBtn = CreateButton(f, "Neue Regel", 100)
    newBtn:SetPoint("BOTTOMLEFT", 14, 14)
    newBtn:SetScript("OnClick", function() LoadEditor(nil) end)

    local runAllBtn = CreateButton(f, "Alle ausführen", 110)
    runAllBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    runAllBtn:SetScript("OnClick", function() RunRules(QuickBankDB.rules) end)

    -- Rechte Seite: Editor -----------------------------------------------
    local X = 240

    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", X, -34)
    nameLabel:SetText("Name:")
    local nameBox = CreateInput(f, 250)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)

    local dirLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dirLabel:SetPoint("TOPLEFT", X, -64)
    dirLabel:SetText("Richtung:")
    local dirBank = CreateCheck(f, "Zur Bank")
    dirBank:SetPoint("LEFT", dirLabel, "RIGHT", 8, 0)
    local dirInv = CreateCheck(f, "Ins Inventar")
    dirInv:SetPoint("LEFT", dirBank, "RIGHT", 70, 0)
    dirBank:SetScript("OnClick", function() dirBank:SetChecked(true); dirInv:SetChecked(false) end)
    dirInv:SetScript("OnClick", function() dirInv:SetChecked(true); dirBank:SetChecked(false) end)

    local typeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeLabel:SetPoint("TOPLEFT", X, -94)
    typeLabel:SetText("Item-Typen:")

    local allBtn = CreateButton(f, "Alle", 60)
    allBtn:SetHeight(18)
    allBtn:SetPoint("LEFT", typeLabel, "RIGHT", 10, 0)
    local noneBtn = CreateButton(f, "Keine", 60)
    noneBtn:SetHeight(18)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)

    local typeScroll, typeContent = CreateScroll(f, 290)
    typeScroll:SetPoint("TOPLEFT", X, -114)
    typeScroll:SetSize(300, 310)

    local typeChecks = {}
    for i, key in ipairs(AllTypeKeys()) do
        local cb = CreateCheck(typeContent, ClassName(key))
        cb:SetPoint("TOPLEFT", 0, -(i - 1) * TYPE_ROW_H)
        typeChecks[key] = cb
    end
    typeContent:SetHeight(#AllTypeKeys() * TYPE_ROW_H)

    allBtn:SetScript("OnClick", function() for _, cb in pairs(typeChecks) do cb:SetChecked(true) end end)
    noneBtn:SetScript("OnClick", function() for _, cb in pairs(typeChecks) do cb:SetChecked(false) end end)

    local saveBtn = CreateButton(f, "Speichern", 100)
    saveBtn:SetPoint("BOTTOMLEFT", X, 14)
    local deleteBtn = CreateButton(f, "Löschen", 90)
    deleteBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    local runBtn = CreateButton(f, "Ausführen", 100)
    runBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

    function LoadEditor(index)
        editIndex = index
        local rule = index and QuickBankDB.rules[index]
        nameBox:SetText(rule and rule.name or "")
        local toBank = not rule or rule.toBank
        dirBank:SetChecked(toBank)
        dirInv:SetChecked(not toBank)
        for key, cb in pairs(typeChecks) do
            cb:SetChecked(rule and rule.types[key] or false)
        end
        deleteBtn:SetEnabled(rule ~= nil)
        runBtn:SetEnabled(rule ~= nil)
        RefreshList()
    end

    saveBtn:SetScript("OnClick", function()
        local name = nameBox:GetText():match("^%s*(.-)%s*$")
        if name == "" then Print("Bitte einen Namen eingeben.") return end
        local types = {}
        for key, cb in pairs(typeChecks) do
            if cb:GetChecked() then types[key] = true end
        end
        if not next(types) then Print("Bitte mindestens einen Item-Typ auswählen.") return end

        local rules = QuickBankDB.rules
        local rule = editIndex and rules[editIndex]
        if not rule then
            rule = { enabled = true }
            rules[#rules + 1] = rule
            editIndex = #rules
        end
        rule.name, rule.toBank, rule.types = name, dirBank:GetChecked() and true or false, types
        Print(('Regel "%s" gespeichert.'):format(name))
        LoadEditor(editIndex)
    end)

    deleteBtn:SetScript("OnClick", function()
        if not editIndex then return end
        local rule = table.remove(QuickBankDB.rules, editIndex)
        Print(('Regel "%s" gelöscht.'):format(rule.name))
        LoadEditor(nil)
    end)

    runBtn:SetScript("OnClick", function()
        local rule = editIndex and QuickBankDB.rules[editIndex]
        if rule then RunRules({ { name = rule.name, toBank = rule.toBank, types = rule.types } }) end
    end)

    function RefreshList()
        local rules = QuickBankDB.rules
        for i, rule in ipairs(rules) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, listContent)
                row:SetSize(180, RULE_ROW_H)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_ROW_H)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.sel = row:CreateTexture(nil, "BACKGROUND")
                row.sel:SetAllPoints()
                row.sel:SetColorTexture(1, 0.82, 0, 0.15)
                row.check = CreateCheck(row)
                row.check:SetPoint("LEFT", 0, 0)
                row.check:SetScript("OnClick", function(cb)
                    QuickBankDB.rules[row.index].enabled = cb:GetChecked() and true or false
                end)
                row.check:SetScript("OnEnter", function(cb)
                    GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Bei \"Aufräumen\" anwenden")
                    GameTooltip:Show()
                end)
                row.check:SetScript("OnLeave", GameTooltip_Hide)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 26, 0)
                row.text:SetPoint("RIGHT", -2, 0)
                row.text:SetJustifyH("LEFT")
                row:SetScript("OnClick", function() LoadEditor(row.index) end)
                rows[i] = row
            end
            row.index = i
            row.check:SetChecked(rule.enabled ~= false)
            row.text:SetText(("%s |cff999999>> %s|r"):format(rule.name, rule.toBank and "Bank" or "Inventar"))
            row.sel:SetShown(i == editIndex)
            row:Show()
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        listContent:SetHeight(math.max(#rules * RULE_ROW_H, 1))
    end

    f:SetScript("OnShow", function() LoadEditor(nil) end)
    tinsert(UISpecialFrames, "QuickBankRulesFrame")
    f:Hide()
    return f
end

local function ToggleRules()
    rulesFrame = rulesFrame or CreateRulesUI()
    rulesFrame:SetShown(not rulesFrame:IsShown())
end

---------------------------------------------------------------------------
-- Hauptfenster aufbauen
---------------------------------------------------------------------------

local function CreateUI()
    frame = CreateFrame("Frame", "QuickBankFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(PANEL_W * 2 + 26 * 2 + 44, 560)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        QuickBankDB.pos = { point, relPoint, x, y }
    end)
    frame:SetScript("OnShow", Refresh)

    local pos = QuickBankDB.pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end

    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("QuickBank")

    -- Obere Leiste: Suche, Regeln, Aufräumen
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 18, -36)
    searchLabel:SetText("Suche:")

    local searchBox = CreateInput(frame, 220)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower():match("^%s*(.-)%s*$")
        Refresh()
    end)

    local tidyBtn = CreateButton(frame, "Aufräumen", 100)
    tidyBtn:SetPoint("TOPRIGHT", -16, -30)
    tidyBtn:SetScript("OnClick", function() RunRules(QuickBankDB.rules) end)
    tidyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Wendet alle aktiven Regeln an")
        GameTooltip:Show()
    end)
    tidyBtn:SetScript("OnLeave", GameTooltip_Hide)

    local rulesBtn = CreateButton(frame, "Regeln", 80)
    rulesBtn:SetPoint("RIGHT", tidyBtn, "LEFT", -4, 0)
    rulesBtn:SetScript("OnClick", ToggleRules)

    bankPanel = CreatePanel(frame, false, 14)
    invPanel = CreatePanel(frame, true, 14 + PANEL_W + 26 + 16)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 12)
    hint:SetText("Shift-Linksklick oder Rechtsklick verschiebt ein Item   |   \"Alle >>\" verschiebt die ganze Kategorie")

    tinsert(UISpecialFrames, "QuickBankFrame") -- ESC schließt das Fenster
    frame:Hide()
end

---------------------------------------------------------------------------
-- Events & Slash-Befehl
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        QuickBankDB = QuickBankDB or {}
        if QuickBankDB.autoOpen == nil then QuickBankDB.autoOpen = true end
        QuickBankDB.rules = QuickBankDB.rules or {}
        CreateUI()
        self:UnregisterEvent("ADDON_LOADED")
        for _, ev in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED",
            "PLAYERBANKSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "BANK_TABS_CHANGED" }) do
            pcall(self.RegisterEvent, self, ev) -- nicht jedes Event existiert in jedem Client
        end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        if QuickBankDB.autoOpen then frame:Show() end
        Refresh()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        StopQueue()
        if QuickBankDB.autoOpen then frame:Hide() end
        Refresh()
    else
        Refresh()
    end
end)

SLASH_QUICKBANK1 = "/quickbank"
SLASH_QUICKBANK2 = "/qb"
SlashCmdList.QUICKBANK = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "auto" then
        QuickBankDB.autoOpen = not QuickBankDB.autoOpen
        Print("Automatisches Öffnen an der Bank: " .. (QuickBankDB.autoOpen and "an" or "aus"))
    elseif msg == "reset" then
        QuickBankDB.pos = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
    elseif msg == "regeln" or msg == "rules" then
        ToggleRules()
    else
        frame:SetShown(not frame:IsShown())
    end
end
