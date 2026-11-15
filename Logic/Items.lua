-- QuickBank: Behälter, Item-Klassifizierung und Suche

local _, ns = ...
local C = C_Container

---------------------------------------------------------------------------
-- Behälter
---------------------------------------------------------------------------

local function AddIfUsable(list, seen, bag)
    if bag and not seen[bag] and (C.GetContainerNumSlots(bag) or 0) > 0 then
        seen[bag] = true
        list[#list + 1] = bag
    end
end

function ns.InventoryBags()
    local list, seen = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do AddIfUsable(list, seen, bag) end
    if Enum.BagIndex and Enum.BagIndex.ReagentBag then
        AddIfUsable(list, seen, Enum.BagIndex.ReagentBag)
    end
    return list
end

function ns.BankBags()
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

-- Quell- bzw. Zielbehälter für eine Verschiebe-Richtung
function ns.SourceBags(toBank) return toBank and ns.InventoryBags() or ns.BankBags() end
function ns.TargetBags(toBank) return toBank and ns.BankBags() or ns.InventoryBags() end

function ns.CountFree(bags)
    local n = 0
    for _, bag in ipairs(bags) do
        local free, family = C.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then n = n + (free or 0) end
    end
    return n
end

-- Ruft fn(bag, slot, info) für jeden belegten Slot der Behälter auf
function ns.ForEachItem(bags, fn)
    for _, bag in ipairs(bags) do
        for slot = 1, C.GetContainerNumSlots(bag) do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID then fn(bag, slot, info) end
        end
    end
end

---------------------------------------------------------------------------
-- Item-Infos
---------------------------------------------------------------------------

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetFullInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

ns.GetQualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

function ns.MaxStack(itemID)
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local s = C_Item.GetItemMaxStackSizeByID(itemID)
        if s then return s end
    end
    local s = GetFullInfo and select(8, GetFullInfo(itemID))
    return s or 1
end

---------------------------------------------------------------------------
-- Kategorien (Gruppenschlüssel = Itemklasse bzw. Material-Untergruppe)
---------------------------------------------------------------------------

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

local function ProfessionName(entry)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, entry[1])
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return entry[2]
end

function ns.ItemCategory(itemID)
    local _, _, _, _, _, classID, subClassID = GetInstant(itemID)
    if classID == TRADEGOODS then return MAT_BASE + (subClassID or 0) end
    return classID or -1
end

local nameCache = {}

function ns.CategoryName(key)
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
function ns.CategoryLess(a, b)
    local am, bm = a >= MAT_BASE, b >= MAT_BASE
    if am ~= bm then return bm end
    return ns.CategoryName(a) < ns.CategoryName(b)
end

-- Alle auswählbaren Kategorien (für die Regeln)
local allCategories
function ns.AllCategories()
    if allCategories then return allCategories end
    local list, seen = {}, {}
    local function add(key)
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = key
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
    table.sort(list, ns.CategoryLess)
    allCategories = list
    return list
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------

function ns.SetSearch(text)
    ns.state.searchText = ns.Trim(text):lower()
    ns.Refresh()
end

function ns.IsSearching()
    return ns.state.searchText ~= ""
end

function ns.MatchesSearch(info)
    local query = ns.state.searchText
    if query == "" then return true end
    local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
    return name ~= nil and name:lower():find(query, 1, true) ~= nil
end
