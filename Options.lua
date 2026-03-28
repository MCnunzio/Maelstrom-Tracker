-- Options.lua (FULL REPLACEMENT)
-- Goals:
--  - Scrollable Interface Options panel
--  - More "Blizzard-native" layout: separators, consistent spacing, 2-column grouping
--  - Filled color swatches (no white centers) with subtle hover border highlight
--  - Shadow/Border color swatches moved UP slightly (less wasted vertical space)

local ADDON_NAME = ...
local PANEL_NAME = "MaelstromTracker"

---------------------------------------------------
-- Safe addon hooks
---------------------------------------------------
local function GetMW()
    return _G["MaelstromTrackerFrame"]
end

local function SafeRefresh()
    local mw = GetMW()
    if mw and mw.Refresh then
        mw:Refresh()
    end
end

local function EnsureDB()
    if not MaelstromTrackerDB then
        MaelstromTrackerDB = {}
    end
end

local function IsInCombatLockdownSafe()
    return (type(InCombatLockdown) == "function") and InCombatLockdown() == true
end

local function IsLoggedInSafe()
    if type(IsLoggedIn) == "function" then
        return IsLoggedIn() == true
    end
    return true
end

---------------------------------------------------
-- Panel + Scroll Frame
---------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = PANEL_NAME

local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetPoint("TOPLEFT", 0, 0)
content:SetSize(1, 1)
scrollFrame:SetScrollChild(content)

local lowestY = -16
local function TrackY(y)
    if y < lowestY then lowestY = y end
end

local function RecalcContentSize()
    local neededHeight = math.abs(lowestY) + 160
    if neededHeight < 650 then neededHeight = 650 end
    content:SetHeight(neededHeight)

    local w = panel:GetWidth()
    if w and w > 50 then
        content:SetWidth(w - 44)
    else
        content:SetWidth(700)
    end
end

panel:SetScript("OnSizeChanged", function()
    RecalcContentSize()
end)

---------------------------------------------------
-- Layout helpers
---------------------------------------------------
local function CreateHeader(parent, text, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    fs:SetText(text)
    TrackY(y)
    return fs
end

local function CreateSubHeader(parent, text, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    fs:SetText(text)
    TrackY(y)
    return fs
end

local function CreateLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    TrackY(y)
    return fs
end

local function CreateSeparator(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    line:SetVertexColor(1, 1, 1, 0.10)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -36, y)
    line:SetHeight(1)
    TrackY(y)
    return line
end

---------------------------------------------------
-- Controls
---------------------------------------------------
local function CreateCheckbox(parent, label, x, y, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.Text:SetText(label)
    TrackY(y)

    if tooltip then
        cb.tooltipText = label
        cb.tooltipRequirement = tooltip
    end

    cb._get = get
    cb._set = set

    cb:SetScript("OnClick", function(self)
        if IsInCombatLockdownSafe() then
            self:SetChecked(get() == true)
            return
        end
        set(self:GetChecked() == true)
        SafeRefresh()
    end)

    return cb
end

local function CreateSlider(parent, label, x, y, minV, maxV, step, get, set, width)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    if width then s:SetWidth(width) end
    TrackY(y)

    if s.Text and s.Text.SetText then
        s.Text:SetText(label)
    end
    if s.Low and s.Low.SetText then
        s.Low:SetText(tostring(minV))
    end
    if s.High and s.High.SetText then
        s.High:SetText(tostring(maxV))
    end

    local val = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    val:SetPoint("LEFT", s, "RIGHT", 8, 0)
    val:SetText("")

    local function UpdateReadout(v)
        if step >= 1 then
            val:SetText(tostring(math.floor(v + 0.5)))
        else
            val:SetText(string.format("%.2f", v))
        end
    end

    s._get = get
    s._set = set

    s:SetScript("OnValueChanged", function(self, v)
        if IsInCombatLockdownSafe() then
            self:SetValue(get())
            return
        end
        set(v)
        UpdateReadout(v)
        SafeRefresh()
    end)

    s:SetScript("OnShow", function(self)
        local v = get()
        self:SetValue(v)
        UpdateReadout(v)
    end)

    return s
end

---------------------------------------------------
-- Color picker helpers
---------------------------------------------------
local function OpenColorPicker(initial, onChanged)
    local r, g, b, a = initial[1], initial[2], initial[3], initial[4] or 1
    local prev = { r = r, g = g, b = b, a = a }

    local info = {
        r = r, g = g, b = b,
        hasOpacity = true,
        opacity = 1 - a,

        swatchFunc = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1 - (ColorPickerFrame.opacity or 0)
            onChanged(nr, ng, nb, na)
        end,

        opacityFunc = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = 1 - (ColorPickerFrame.opacity or 0)
            onChanged(nr, ng, nb, na)
        end,

        cancelFunc = function()
            onChanged(prev.r, prev.g, prev.b, prev.a)
        end,
    }

    ColorPickerFrame:SetupColorPickerAndShow(info)
end

-- Filled swatch (Blizzard-ish): small square w/ border + hover highlight
local function CreateColorSwatch(parent, label, x, y, getTable, setTable)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(260, 20)
    btn:EnableMouse(true)
    TrackY(y)

    local sw = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
    sw:SetPoint("LEFT", btn, "LEFT", 0, 0)
    sw:SetSize(18, 18)
    sw:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sw:SetBackdropBorderColor(0, 0, 0, 0.85)

    local txt = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    txt:SetText(label)

    local function ApplyColor()
        local c = getTable()
        local r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        sw:SetBackdropColor(r, g, b, a)
    end

    btn:SetScript("OnClick", function()
        if IsInCombatLockdownSafe() then return end
        local c = getTable()
        OpenColorPicker(c, function(r, g, b, a)
            setTable({ r, g, b, a })
            ApplyColor()
            SafeRefresh()
        end)
    end)

    btn:SetScript("OnEnter", function()
        sw:SetBackdropBorderColor(1, 1, 1, 0.9)
    end)
    btn:SetScript("OnLeave", function()
        sw:SetBackdropBorderColor(0, 0, 0, 0.85)
    end)

    btn._get = ApplyColor
    return btn
end

---------------------------------------------------
-- DB getters/setters
---------------------------------------------------
local controls = {}

local function GetOrDefault(key, default)
    EnsureDB()
    local v = MaelstromTrackerDB[key]
    if v == nil then return default end
    return v
end

local function SetKey(key, value)
    EnsureDB()
    MaelstromTrackerDB[key] = value
end

local function GetColorKey(key, fallback)
    EnsureDB()
    local t = MaelstromTrackerDB[key]
    if type(t) ~= "table" then t = fallback end
    return t
end

local function SetColorKey(key, rgba)
    EnsureDB()
    MaelstromTrackerDB[key] = { rgba[1], rgba[2], rgba[3], rgba[4] }
end

---------------------------------------------------
-- Build UI (on content)
---------------------------------------------------
local function BuildUI()
    if panel._built then return end
    panel._built = true

    EnsureDB()
    lowestY = -16

    -- Column constants (more “native” alignment)
    local L = 16
    local R = 330
    local SLW = 200

    CreateHeader(content, "MaelstromTracker", -16)
    CreateLabel(content, "Midnight (12.x) safe options. Changes apply immediately.", L, -44)

    CreateSeparator(content, -62)

    -------------------------------------------------
    -- Main Bar
    -------------------------------------------------
    CreateSubHeader(content, "Main Bar", -86)

    table.insert(controls, CreateCheckbox(content, "Locked (drag disabled when checked)", L, -116,
        function() return GetOrDefault("locked", true) end,
        function(v) SetKey("locked", v) end))

    table.insert(controls, CreateCheckbox(content, "Show only in combat", L, -146,
        function() return GetOrDefault("onlyInCombat", false) end,
        function(v) SetKey("onlyInCombat", v) end))

    table.insert(controls, CreateCheckbox(content, "Show stack text", L, -176,
        function() return GetOrDefault("showStackText", true) end,
        function(v) SetKey("showStackText", v) end))

    table.insert(controls, CreateCheckbox(content, "Glow at 10 stacks", L, -206,
        function() return GetOrDefault("glowAtTen", true) end,
        function(v) SetKey("glowAtTen", v) end))

    table.insert(controls, CreateSlider(content, "Bar width", R, -116, 120, 600, 5,
        function() return tonumber(GetOrDefault("width", 250)) or 250 end,
        function(v) SetKey("width", math.floor(v + 0.5)) end, SLW))

    table.insert(controls, CreateSlider(content, "Bar height", R, -176, 8, 60, 1,
        function() return tonumber(GetOrDefault("height", 20)) or 20 end,
        function(v) SetKey("height", math.floor(v + 0.5)) end, SLW))

    CreateSeparator(content, -238)

    -------------------------------------------------
    -- Colors
    -------------------------------------------------
    CreateSubHeader(content, "Colors", -264)

    table.insert(controls, CreateColorSwatch(content, "Text Color", L, -294,
        function() return GetColorKey("textColor", {1,1,1,1}) end,
        function(rgba) SetColorKey("textColor", rgba) end))

    table.insert(controls, CreateColorSwatch(content, "0 stacks color", L, -324,
        function() return GetColorKey("colorZero", {0.25,0.25,0.25,1}) end,
        function(rgba) SetColorKey("colorZero", rgba) end))

    table.insert(controls, CreateColorSwatch(content, "1–5 stacks color", L, -354,
        function() return GetColorKey("colorBlue", {0.10,0.65,1.00,1}) end,
        function(rgba) SetColorKey("colorBlue", rgba) end))

    table.insert(controls, CreateColorSwatch(content, "6–9 stacks color", L, -384,
        function() return GetColorKey("colorOrange", {0.05,0.35,0.85,1}) end,
        function(rgba) SetColorKey("colorOrange", rgba) end))

    table.insert(controls, CreateColorSwatch(content, "10 stacks color", L, -414,
        function() return GetColorKey("colorRed", {1.00,0.10,0.10,1}) end,
        function(rgba) SetColorKey("colorRed", rgba) end))

    CreateSeparator(content, -448)

    -------------------------------------------------
    -- Border & Shadow (2 column group)
    -------------------------------------------------
    CreateSubHeader(content, "Border & Shadow", -474)

    -- Checkboxes row
    table.insert(controls, CreateCheckbox(content, "Shadow enabled", L, -504,
        function() return GetOrDefault("shadowEnabled", true) end,
        function(v) SetKey("shadowEnabled", v) end))

    table.insert(controls, CreateCheckbox(content, "Border enabled", R, -504,
        function() return GetOrDefault("borderEnabled", true) end,
        function(v) SetKey("borderEnabled", v) end))

    -- Sliders row (space below checkbox, but not huge)
    table.insert(controls, CreateSlider(content, "Shadow size", L, -548, 0, 20, 1,
        function() return tonumber(GetOrDefault("shadowSize", 4)) or 4 end,
        function(v) SetKey("shadowSize", math.floor(v + 0.5)) end, SLW))

    table.insert(controls, CreateSlider(content, "Border thickness", R, -548, 1, 12, 1,
        function() return tonumber(GetOrDefault("borderThickness", 2)) or 2 end,
        function(v) SetKey("borderThickness", math.floor(v + 0.5)) end, SLW))

    table.insert(controls, CreateSlider(content, "Border padding", R, -608, 0, 10, 1,
        function() return tonumber(GetOrDefault("borderPadding", 1)) or 1 end,
        function(v) SetKey("borderPadding", math.floor(v + 0.5)) end, SLW))

    -- Color swatches moved UP (less spacing than before)
    table.insert(controls, CreateColorSwatch(content, "Shadow color", L, -604,
        function() return GetColorKey("shadowColor", {0,0,0,0.65}) end,
        function(rgba) SetColorKey("shadowColor", rgba) end))

    table.insert(controls, CreateColorSwatch(content, "Border color", R, -668,
        function() return GetColorKey("borderColor", {1,1,1,0.85}) end,
        function(rgba) SetColorKey("borderColor", rgba) end))

    CreateSeparator(content, -714)

    -------------------------------------------------
    -- Weapon Imbuements Tracker
    -------------------------------------------------
    CreateSubHeader(content, "Weapon Imbuements Tracker", -740)

    table.insert(controls, CreateCheckbox(content, "Enable weapon imbuements tracker", L, -770,
        function() return GetOrDefault("imbueTrackerEnabled", true) end,
        function(v) SetKey("imbueTrackerEnabled", v) end))

    table.insert(controls, CreateCheckbox(content, "Imbue tracker locked (drag disabled)", L, -800,
        function() return GetOrDefault("imbueLocked", true) end,
        function(v) SetKey("imbueLocked", v) end))

    table.insert(controls, CreateSlider(content, "Imbue icon size", R, -770, 16, 64, 1,
        function() return tonumber(GetOrDefault("imbueIconSize", 28)) or 28 end,
        function(v) SetKey("imbueIconSize", math.floor(v + 0.5)) end, SLW))

    table.insert(controls, CreateSlider(content, "Warn when time < (seconds)", R, -830, 10, 600, 5,
        function() return tonumber(GetOrDefault("imbueWarnSeconds", 60)) or 60 end,
        function(v) SetKey("imbueWarnSeconds", math.floor(v + 0.5)) end, SLW))

    table.insert(controls, CreateSlider(content, "Trust grace after transitions (sec)", R, -890, 0, 8, 0.5,
        function() return tonumber(GetOrDefault("imbueTrustGraceSeconds", 1.5)) or 1.5 end,
        function(v) SetKey("imbueTrustGraceSeconds", math.floor((v * 10) + 0.5) / 10) end, SLW))

    table.insert(controls, CreateCheckbox(content, "Hide warnings when buff state is untrusted", L, -850,
        function() return GetOrDefault("imbueHideWhenUntrusted", true) end,
        function(v) SetKey("imbueHideWhenUntrusted", v) end,
        "Recommended. During combat or short transition windows, hide warnings until fresh reads are confirmed."))

    table.insert(controls, CreateCheckbox(content, "Hide weapon imbuements warnings in sanctuary zones", L, -885,
        function() return GetOrDefault("imbueHideInSanctuary", false) end,
        function(v) SetKey("imbueHideInSanctuary", v) end,
        "Uses GetZonePVPInfo() == 'sanctuary'. Useful to suppress reminders in cities/rest areas."))

    panel.refresh = function()
        EnsureDB()
        for _, c in ipairs(controls) do
            if c._get then
                if c.GetObjectType and c:GetObjectType() == "CheckButton" then
                    c:SetChecked(c._get() == true)
                elseif c.GetObjectType and c:GetObjectType() == "Slider" then
                    c:SetValue(c._get())
                else
                    c._get()
                end
            end
        end
    end

    RecalcContentSize()
end

panel:SetScript("OnShow", function()
    BuildUI()
    if panel.refresh then panel.refresh() end
    RecalcContentSize()
end)

---------------------------------------------------
-- Register panel (deferred)
---------------------------------------------------
local registered = false
local function RegisterPanel()
    if registered then return true end
    if not IsLoggedInSafe() then return false end
    if IsInCombatLockdownSafe() then return false end

    local ok = pcall(function()
        if type(InterfaceOptions_AddCategory) == "function" then
            InterfaceOptions_AddCategory(panel)
        elseif Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
            and type(Settings.RegisterAddOnCategory) == "function" then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
            cat.ID = panel.name
            Settings.RegisterAddOnCategory(cat)
        end
    end)

    if ok then
        registered = true
        return true
    end
    return false
end

local regFrame = CreateFrame("Frame")
regFrame._elapsed = 0
regFrame:SetScript("OnUpdate", function(self, elapsed)
    self._elapsed = (self._elapsed or 0) + (elapsed or 0)
    if self._elapsed < 0.5 then return end
    self._elapsed = 0
    if RegisterPanel() then
        self:SetScript("OnUpdate", nil)
    end
end)

SLASH_MAELSTROMTRACKER1 = "/maelstromtracker"
SLASH_MAELSTROMTRACKER2 = "/mt"
SlashCmdList["MAELSTROMTRACKER"] = function()
    RegisterPanel()
    BuildUI()
    if panel.refresh then panel.refresh() end
    RecalcContentSize()

    if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
        return
    end

    if Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(panel.name)
    end
end
