-- QuickBank: wiederverwendbare UI-Bausteine

local _, ns = ...

local W = {}
ns.Widgets = W

function W.Check(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    return cb
end

function W.Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 22)
    b:SetText(text)
    return b
end

function W.Input(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

function W.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text or "")
    return fs
end

-- ScrollFrame mit Inhalts-Frame; Größe/Position setzt der Aufrufer
function W.Scroll(parent, contentWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

function W.Tooltip(widget, text, anchor)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- Verschiebbares Fenster mit Titel, schließbar per ESC
function W.Window(name, title, width, height, strata)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(width, height)
    f:SetFrameStrata(strata or "HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local fs = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOP", 0, -5)
    end
    fs:SetText(title)

    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end
