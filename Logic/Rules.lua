-- QuickBank: Regeln (gespeichert in QuickBankDB.rules)
-- Regel: { name = string, toBank = bool, enabled = bool, types = { [Kategorie] = true } }

local _, ns = ...

function ns.GetRules()
    return QuickBankDB.rules
end

function ns.GetRule(index)
    return index and QuickBankDB.rules[index]
end

-- Legt eine Regel an (index = nil) oder ändert sie.
-- Liefert den Index oder nil + Fehlermeldung.
function ns.SaveRule(index, name, toBank, types)
    name = ns.Trim(name)
    if name == "" then return nil, "Bitte einen Namen eingeben." end
    if not next(types) then return nil, "Bitte mindestens einen Item-Typ auswählen." end

    local rules = QuickBankDB.rules
    local rule = rules[index]
    if not rule then
        rule = { enabled = true }
        rules[#rules + 1] = rule
        index = #rules
    end
    rule.name, rule.toBank, rule.types = name, toBank and true or false, types
    return index
end

function ns.DeleteRule(index)
    return table.remove(QuickBankDB.rules, index)
end

function ns.SetRuleEnabled(index, enabled)
    local rule = ns.GetRule(index)
    if rule then rule.enabled = enabled and true or false end
end

local function IsActive(rule)
    return rule.enabled ~= false and rule.types and next(rule.types) ~= nil
end

local function Apply(rule)
    local n = ns.MoveWhere(rule.toBank, function(info)
        return rule.types[ns.ItemCategory(info.itemID)]
    end)
    ns.ReportMove(n, rule.name, rule.toBank)
    return n
end

-- Wendet alle aktiven Regeln an
function ns.RunAllRules()
    if not ns.RequireBank() then return end
    local total = 0
    for _, rule in ipairs(QuickBankDB.rules) do
        if IsActive(rule) then total = total + Apply(rule) end
    end
    if total == 0 then ns.Print("Regeln: nichts zu verschieben.") end
end

-- Wendet eine einzelne Regel an (auch wenn sie deaktiviert ist)
function ns.RunRule(index)
    local rule = ns.GetRule(index)
    if not rule or not ns.RequireBank() then return end
    if Apply(rule) == 0 then ns.Print(('Regel "%s": nichts zu verschieben.'):format(rule.name)) end
end
