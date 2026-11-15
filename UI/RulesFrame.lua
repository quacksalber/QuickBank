-- QuickBank: Fenster zum Anlegen und Bearbeiten von Regeln

local _, ns = ...
local W = ns.Widgets

local ROW_H = 22
local EDITOR_X = 240

local frame
local editIndex -- Index der bearbeiteten Regel, nil = neue Regel
local ui = {}   -- Editor-Elemente
local rows = {} -- Zeilen der Regelliste

local LoadEditor -- vorwärts deklariert

---------------------------------------------------------------------------
-- Regelliste (links)
---------------------------------------------------------------------------

local function CreateRuleRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(180, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.15)

    row.check = W.Check(row)
    row.check:SetPoint("LEFT")
    row.check:SetScript("OnClick", function(cb) ns.SetRuleEnabled(row.index, cb:GetChecked()) end)
    W.Tooltip(row.check, "Bei \"Aufräumen\" anwenden")

    row.text = W.Label(row, nil, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 26, 0)
    row.text:SetPoint("RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function() LoadEditor(row.index) end)
    return row
end

local function RefreshList()
    local rules = ns.GetRules()
    for i, rule in ipairs(rules) do
        rows[i] = rows[i] or CreateRuleRow(ui.listContent, i)
        local row = rows[i]
        row.index = i
        row.check:SetChecked(rule.enabled ~= false)
        row.text:SetText(("%s |cff999999>> %s|r"):format(rule.name, rule.toBank and "Bank" or "Inventar"))
        row.sel:SetShown(i == editIndex)
        row:Show()
    end
    for i = #rules + 1, #rows do rows[i]:Hide() end
    ui.listContent:SetHeight(math.max(#rules * ROW_H, 1))
end

local function CreateList(f)
    local label = W.Label(f, "Regeln")
    label:SetPoint("TOPLEFT", 16, -34)

    local scroll
    scroll, ui.listContent = W.Scroll(f, 190)
    scroll:SetPoint("TOPLEFT", 12, -54)
    scroll:SetSize(190, 370)

    local newBtn = W.Button(f, "Neue Regel", 100)
    newBtn:SetPoint("BOTTOMLEFT", 14, 14)
    newBtn:SetScript("OnClick", function() LoadEditor(nil) end)

    local runAllBtn = W.Button(f, "Alle ausführen", 110)
    runAllBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    runAllBtn:SetScript("OnClick", ns.RunAllRules)
end

---------------------------------------------------------------------------
-- Editor (rechts)
---------------------------------------------------------------------------

local function SetDirection(toBank)
    ui.dirBank:SetChecked(toBank)
    ui.dirInv:SetChecked(not toBank)
end

local function SetAllTypes(checked)
    for _, cb in pairs(ui.typeChecks) do cb:SetChecked(checked) end
end

local function SelectedTypes()
    local types = {}
    for key, cb in pairs(ui.typeChecks) do
        if cb:GetChecked() then types[key] = true end
    end
    return types
end

function LoadEditor(index)
    editIndex = index
    local rule = ns.GetRule(index)
    ui.name:SetText(rule and rule.name or "")
    SetDirection(not rule or rule.toBank)
    for key, cb in pairs(ui.typeChecks) do
        cb:SetChecked(rule and rule.types[key] or false)
    end
    ui.delete:SetEnabled(rule ~= nil)
    ui.run:SetEnabled(rule ~= nil)
    RefreshList()
end

local function OnSave()
    local index, err = ns.SaveRule(editIndex, ui.name:GetText(), ui.dirBank:GetChecked(), SelectedTypes())
    if not index then ns.Print(err) return end
    ns.Print(('Regel "%s" gespeichert.'):format(ns.GetRule(index).name))
    LoadEditor(index)
end

local function OnDelete()
    if not editIndex then return end
    local rule = ns.DeleteRule(editIndex)
    ns.Print(('Regel "%s" gelöscht.'):format(rule.name))
    LoadEditor(nil)
end

local function CreateEditor(f)
    local nameLabel = W.Label(f, "Name:")
    nameLabel:SetPoint("TOPLEFT", EDITOR_X, -34)
    ui.name = W.Input(f, 250)
    ui.name:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)

    local dirLabel = W.Label(f, "Richtung:")
    dirLabel:SetPoint("TOPLEFT", EDITOR_X, -64)
    ui.dirBank = W.Check(f, "Zur Bank")
    ui.dirBank:SetPoint("LEFT", dirLabel, "RIGHT", 8, 0)
    ui.dirBank:SetScript("OnClick", function() SetDirection(true) end)
    ui.dirInv = W.Check(f, "Ins Inventar")
    ui.dirInv:SetPoint("LEFT", ui.dirBank, "RIGHT", 70, 0)
    ui.dirInv:SetScript("OnClick", function() SetDirection(false) end)

    local typeLabel = W.Label(f, "Item-Typen:")
    typeLabel:SetPoint("TOPLEFT", EDITOR_X, -94)
    local allBtn = W.Button(f, "Alle", 60, 18)
    allBtn:SetPoint("LEFT", typeLabel, "RIGHT", 10, 0)
    allBtn:SetScript("OnClick", function() SetAllTypes(true) end)
    local noneBtn = W.Button(f, "Keine", 60, 18)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
    noneBtn:SetScript("OnClick", function() SetAllTypes(false) end)

    local scroll, content = W.Scroll(f, 290)
    scroll:SetPoint("TOPLEFT", EDITOR_X, -114)
    scroll:SetSize(300, 310)

    ui.typeChecks = {}
    local categories = ns.AllCategories()
    for i, key in ipairs(categories) do
        local cb = W.Check(content, ns.CategoryName(key))
        cb:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        ui.typeChecks[key] = cb
    end
    content:SetHeight(#categories * ROW_H)

    local saveBtn = W.Button(f, "Speichern", 100)
    saveBtn:SetPoint("BOTTOMLEFT", EDITOR_X, 14)
    saveBtn:SetScript("OnClick", OnSave)

    ui.delete = W.Button(f, "Löschen", 90)
    ui.delete:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    ui.delete:SetScript("OnClick", OnDelete)

    ui.run = W.Button(f, "Ausführen", 100)
    ui.run:SetPoint("LEFT", ui.delete, "RIGHT", 4, 0)
    ui.run:SetScript("OnClick", function() ns.RunRule(editIndex) end)
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function CreateRulesFrame()
    frame = W.Window("QuickBankRulesFrame", "QuickBank - Regeln", 580, 480, "DIALOG")
    frame:SetPoint("CENTER")
    CreateList(frame)
    CreateEditor(frame)
    frame:SetScript("OnShow", function() LoadEditor(nil) end)
end

function ns.ToggleRules()
    if not frame then CreateRulesFrame() end
    frame:SetShown(not frame:IsShown())
end
