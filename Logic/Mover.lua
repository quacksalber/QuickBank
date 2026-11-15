-- QuickBank: Verschiebe-Warteschlange
-- Verschiebt ein Item nach dem anderen und wartet jeweils auf die Bestätigung des Servers.

local _, ns = ...
local C = C_Container
local Print = ns.Print

local TICK = 0.05     -- Sekunden zwischen zwei Schritten
local TIMEOUT = 2     -- Sekunden, die auf den Server gewartet wird
local MAX_TRIES = 40  -- Versuche bei gesperrten Items

local queue, queued, reserved, badBags, badSlots = {}, {}, {}, {}, {}
local current, ticker

local function Key(bag, slot) return bag .. ":" .. slot end

local function Push(job, front)
    queued[Key(job.bag, job.slot)] = true
    if front then table.insert(queue, 1, job) else queue[#queue + 1] = job end
end

local function Pop()
    local job = table.remove(queue, 1)
    if job then queued[Key(job.bag, job.slot)] = nil end
    return job
end

function ns.StopQueue()
    wipe(queue)
    wipe(queued)
    current = nil
    if ticker then ticker:Cancel(); ticker = nil end
end

---------------------------------------------------------------------------
-- Zielsuche
---------------------------------------------------------------------------

local function IsReserved(k, now)
    return reserved[k] and reserved[k] > now
end

-- Teilstapel desselben Items, in den noch etwas passt
local function FindPartialStack(bags, itemID, now)
    local max = ns.MaxStack(itemID)
    if max <= 1 then return end
    for _, bag in ipairs(bags) do
        if not badBags[bag] then
            for slot = 1, C.GetContainerNumSlots(bag) do
                local k = Key(bag, slot)
                local info = C.GetContainerItemInfo(bag, slot)
                local count = info and (info.stackCount or 1)
                if info and info.itemID == itemID and not info.isLocked and count < max
                    and not badSlots[k] and not IsReserved(k, now) then
                    return bag, slot, max - count
                end
            end
        end
    end
end

-- Freier Slot in einem normalen (nicht spezialisierten) Behälter
local function FindFreeSlot(bags, now)
    for _, bag in ipairs(bags) do
        local free, family = C.GetContainerNumFreeSlots(bag)
        if not badBags[bag] and (family or 0) == 0 and (free or 0) > 0 then
            for slot = 1, C.GetContainerNumSlots(bag) do
                if not C.GetContainerItemInfo(bag, slot) and not IsReserved(Key(bag, slot), now) then
                    return bag, slot
                end
            end
        end
    end
end

-- Rückgabe: bag, slot, room (Platz im Teilstapel; nil bei freiem Slot)
local function FindTarget(toBank, itemID)
    local now, bags = GetTime(), ns.TargetBags(toBank)
    local bag, slot, room = FindPartialStack(bags, itemID, now)
    if bag then return bag, slot, room end
    return FindFreeSlot(bags, now)
end

---------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------

-- Prüft den laufenden Zug. true = weiter warten.
local function AwaitCurrent()
    if not current then return false end
    local info = C.GetContainerItemInfo(current.bag, current.slot)
    local same = info and info.itemID == current.itemID
    if same and (info.isLocked or info.stackCount == current.count) and GetTime() < current.deadline then
        return true
    end
    local done = current
    current = nil
    reserved[done.dest] = nil
    -- Nur ein Teil passte in den Ziel-Stapel: Rest erneut einreihen
    if same and done.partial and (info.stackCount or 0) < done.count then
        Push(done, true)
    end
    return false
end

-- Führt einen Zug aus. Liefert false, wenn die Warteschlange abgebrochen werden muss.
local function Execute(job, info)
    if GetCursorInfo() then
        Print("Abgebrochen: es liegt etwas auf dem Cursor.")
        return false
    end

    local dBag, dSlot, room = FindTarget(job.toBank, job.itemID)
    if not dBag then
        Print(job.toBank and "Die Bank ist voll." or "Das Inventar ist voll.")
        return false
    end

    local count = info.stackCount or 1
    local partial = room ~= nil and room < count
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
        return true
    end

    job.dest = Key(dBag, dSlot)
    reserved[job.dest] = GetTime() + TIMEOUT
    job.count, job.partial = count, partial
    job.deadline = GetTime() + TIMEOUT
    current = job
    return true
end

local function Step()
    if not ns.state.bankOpen then ns.StopQueue() return end
    if AwaitCurrent() then return end

    local job = Pop()
    if not job then ns.StopQueue() return end

    local info = C.GetContainerItemInfo(job.bag, job.slot)
    if not info or info.itemID ~= job.itemID then return end -- Slot hat sich geändert

    if info.isLocked then
        job.tries = (job.tries or 0) + 1
        if job.tries < MAX_TRIES then
            Push(job)
        else
            Print(("%s ist gesperrt und wurde übersprungen."):format(info.hyperlink or "Item"))
        end
        return
    end

    if not Execute(job, info) then ns.StopQueue() end
end

---------------------------------------------------------------------------
-- Öffentliche Schnittstelle
---------------------------------------------------------------------------

function ns.RequireBank()
    if ns.state.bankOpen then return true end
    Print("Die Bank muss geöffnet sein.")
    return false
end

-- Reiht einen Slot ein. Liefert true, wenn er neu eingereiht wurde.
function ns.Enqueue(bag, slot, itemID, toBank)
    if not ns.state.bankOpen or queued[Key(bag, slot)] then return false end
    if not ticker then
        wipe(badBags)
        wipe(badSlots)
        wipe(reserved)
        ticker = C_Timer.NewTicker(TICK, Step)
    end
    Push({ bag = bag, slot = slot, itemID = itemID, toBank = toBank })
    return true
end

-- Reiht alle Items der Quellseite ein, auf die pred(info) zutrifft. Liefert die Anzahl.
function ns.MoveWhere(toBank, pred)
    local n = 0
    ns.ForEachItem(ns.SourceBags(toBank), function(bag, slot, info)
        if pred(info) and ns.Enqueue(bag, slot, info.itemID, toBank) then n = n + 1 end
    end)
    return n
end

function ns.ReportMove(n, what, toBank)
    if n > 0 then
        Print(("%dx %s >> %s"):format(n, what, toBank and "Bank" or "Inventar"))
    end
end

function ns.MoveItem(bag, slot, itemID, toBank)
    if ns.RequireBank() then ns.Enqueue(bag, slot, itemID, toBank) end
end

function ns.MoveCategory(key, toBank)
    if not ns.RequireBank() then return end
    local n = ns.MoveWhere(toBank, function(info)
        return ns.ItemCategory(info.itemID) == key and ns.MatchesSearch(info)
    end)
    ns.ReportMove(n, ns.CategoryName(key), toBank)
end

function ns.MoveSearchResults(toBank)
    if not ns.RequireBank() then return end
    local n = ns.MoveWhere(toBank, ns.MatchesSearch)
    ns.ReportMove(n, ('"%s"'):format(ns.state.searchText), toBank)
end
