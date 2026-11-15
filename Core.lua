-- QuickBank: gemeinsamer Namespace, Zustand und Hilfsfunktionen

local _, ns = ...

ns.PREFIX = "|cff33ff99QuickBank|r: "

-- Gemeinsamer Laufzeit-Zustand
ns.state = {
    bankOpen = false,
    searchText = "", -- bereits kleingeschrieben und getrimmt
}

function ns.Print(msg)
    print(ns.PREFIX .. msg)
end

function ns.Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- Wird von der UI gesetzt; Logik-Module rufen nur ns.Refresh() auf
function ns.Refresh() end
