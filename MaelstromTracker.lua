-- MaelstromTracker.lua (FULL REPLACEMENT)
-- Fixes / Features:
--  1) Imbue tracker strata lowered (won't sit above Options)
--  2) Dragging not jumpy (ticker never relayouts / SetPoint)
--  3) Imbue icons show ONLY when warning is needed (missing or remaining < threshold)
--  4) Ticker pauses while dragging
--  5) Debounced warnings (2 consecutive "bad" reads required) to prevent combat-start flicker
--  6) Talent-aware behavior:
--     - If Instinctive Imbuements is chosen: ONLY show Lightning Shield when missing (no threshold)
--     - If NOT chosen: show Lightning Shield + Windfury + Flametongue when missing OR remaining < threshold
--  7) Layout: when NOT instinctive, Imbue frame supports 3 icons in a row (LS + WF + FT)
--  8) Midnight API-safe: NO UnitBuff / UnitAura usage (those can be nil in Midnight builds)
--     Uses AuraUtil + C_UnitAuras only.
--  9) Combat-safe: NEVER queries restricted auras (e.g., Lightning Shield) in combat.
--     Weapon Imbuements tracker is hidden in combat and imbue updates are paused.

local ADDON_NAME = ...
local MW = CreateFrame("Frame", "MaelstromTrackerFrame", UIParent)

local SPELL_ID = 344179 -- Maelstrom Weapon
local MAX_STACKS = 10
local SEGMENTS = 5

-- Spell IDs
local SPELL_FLAMETONGUE = 318038
local SPELL_WINDFURY    = 33757
local SPELL_LSHIELD     = 192106
local SPELL_EARTH_SHIELD = 974
local SPELL_INSTINCTIVE_IMBUEMENTS = 1270350
local SPEC_ID_ELEMENTAL = 262
local SPEC_ID_ENHANCEMENT = 263

local defaults = {
    width = 250,
    height = 20,
    point = "CENTER",
    x = 0,
    y = -150,

    glowAtTen = true,
    locked = true,
    onlyInCombat = false,

    showStackText = true,
    textColor = { 1, 1, 1, 1 }, -- RGBA

    -- Bar colors (RGBA)
    colorZero   = { 0.25, 0.25, 0.25, 1 },   -- 0 stacks
    colorBlue   = { 0.10, 0.65, 1.00, 1 },   -- 1-5 stacks
    colorOrange = { 0.05, 0.35, 0.85, 1 },   -- 6-9 stacks
    colorRed    = { 1.00, 0.10, 0.10, 1 },   -- 10 stacks

    borderEnabled = true,
    borderThickness = 2,
    borderPadding = 1,
    borderColor = { 1, 1, 1, 0.85 },

    shadowEnabled = true,
    shadowSize = 4,
    shadowColor = { 0, 0, 0, 0.65 },

    -- Independent Weapon Imbuements Tracker
    imbueTrackerEnabled = true,
    imbueHideInSanctuary = false,
    imbueLocked = true,
    imbuePoint = "CENTER",
    imbueX = 0,
    imbueY = -110,
    imbueWarnSeconds = 60,   -- warn if missing or remaining < this (when NOT instinctive)
    imbueIconSize = 28,
    imbueTrustGraceSeconds = 1.5,
    imbueHideWhenUntrusted = true,
}

---------------------------------------------------
-- DB helpers
---------------------------------------------------
local function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            local inner = {}
            for i = 1, #v do inner[i] = v[i] end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local function Clamp01(n)
    n = tonumber(n) or 0
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function EnsureColor(tbl, key, fallback)
    if type(tbl[key]) ~= "table" or #tbl[key] < 3 then
        tbl[key] = { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
        return
    end
    tbl[key][1] = Clamp01(tbl[key][1])
    tbl[key][2] = Clamp01(tbl[key][2])
    tbl[key][3] = Clamp01(tbl[key][3])
    tbl[key][4] = Clamp01(tbl[key][4] or 1)
end

local function InitDB()
    if not MaelstromTrackerDB then MaelstromTrackerDB = {} end

    for k, v in pairs(defaults) do
        if MaelstromTrackerDB[k] == nil then
            MaelstromTrackerDB[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end

    MaelstromTrackerDB.point = MaelstromTrackerDB.point or "CENTER"
    MaelstromTrackerDB.x = tonumber(MaelstromTrackerDB.x) or 0
    MaelstromTrackerDB.y = tonumber(MaelstromTrackerDB.y) or -150
    MaelstromTrackerDB.width = tonumber(MaelstromTrackerDB.width) or defaults.width
    MaelstromTrackerDB.height = tonumber(MaelstromTrackerDB.height) or defaults.height

    MaelstromTrackerDB.imbuePoint = MaelstromTrackerDB.imbuePoint or "CENTER"
    MaelstromTrackerDB.imbueX = tonumber(MaelstromTrackerDB.imbueX) or defaults.imbueX
    MaelstromTrackerDB.imbueY = tonumber(MaelstromTrackerDB.imbueY) or defaults.imbueY

    MaelstromTrackerDB.imbueWarnSeconds = tonumber(MaelstromTrackerDB.imbueWarnSeconds) or defaults.imbueWarnSeconds
    if MaelstromTrackerDB.imbueWarnSeconds < 10 then MaelstromTrackerDB.imbueWarnSeconds = 10 end
    if MaelstromTrackerDB.imbueWarnSeconds > 600 then MaelstromTrackerDB.imbueWarnSeconds = 600 end

    MaelstromTrackerDB.imbueIconSize = tonumber(MaelstromTrackerDB.imbueIconSize) or defaults.imbueIconSize
    if MaelstromTrackerDB.imbueIconSize < 16 then MaelstromTrackerDB.imbueIconSize = 16 end
    if MaelstromTrackerDB.imbueIconSize > 64 then MaelstromTrackerDB.imbueIconSize = 64 end

    MaelstromTrackerDB.imbueTrustGraceSeconds = tonumber(MaelstromTrackerDB.imbueTrustGraceSeconds) or defaults.imbueTrustGraceSeconds
    if MaelstromTrackerDB.imbueTrustGraceSeconds < 0 then MaelstromTrackerDB.imbueTrustGraceSeconds = 0 end
    if MaelstromTrackerDB.imbueTrustGraceSeconds > 8 then MaelstromTrackerDB.imbueTrustGraceSeconds = 8 end
    if MaelstromTrackerDB.imbueHideWhenUntrusted == nil then
        MaelstromTrackerDB.imbueHideWhenUntrusted = defaults.imbueHideWhenUntrusted
    end

    EnsureColor(MaelstromTrackerDB, "textColor", defaults.textColor)
    EnsureColor(MaelstromTrackerDB, "borderColor", defaults.borderColor)
    EnsureColor(MaelstromTrackerDB, "shadowColor", defaults.shadowColor)

    EnsureColor(MaelstromTrackerDB, "colorZero", defaults.colorZero)
    EnsureColor(MaelstromTrackerDB, "colorBlue", defaults.colorBlue)
    EnsureColor(MaelstromTrackerDB, "colorOrange", defaults.colorOrange)
    EnsureColor(MaelstromTrackerDB, "colorRed", defaults.colorRed)

    -- Cleanup / migrations (older versions used these)
    MaelstromTrackerDB.imbueOnlyInCombat = nil
    MaelstromTrackerDB.imbueWarnInCombat = nil
end

---------------------------------------------------
-- Spell icon helper
---------------------------------------------------
local function GetSpellIcon(spellId)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    if type(GetSpellTexture) == "function" then
        local tex = GetSpellTexture(spellId)
        if tex then return tex end
    end
    if type(GetSpellInfo) == "function" then
        local _, _, icon = GetSpellInfo(spellId)
        if icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

---------------------------------------------------
-- Aura helpers (Midnight-safe: no UnitBuff/UnitAura)
---------------------------------------------------
local function GetSpellNameSafe(spellId)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        return C_Spell.GetSpellName(spellId)
    end
    if type(GetSpellInfo) == "function" then
        return GetSpellInfo(spellId)
    end
    return nil
end

-- Returns (found:boolean, remainingSeconds:number|nil, stacks:number|nil)
-- remainingSeconds nil when aura has no meaningful expiration
local function GetPlayerAuraStatus(spellId)
    local now = GetTime()

    -- 1) AuraUtil Find by SpellID (preferred)
    if AuraUtil and type(AuraUtil.FindAuraBySpellId) == "function" then
        local name, _, count, _, _, expirationTime = AuraUtil.FindAuraBySpellId(spellId, "player", "HELPFUL")
        if name then
            if expirationTime and expirationTime > 0 then
                return true, expirationTime - now, count
            end
            return true, nil, count
        end
    end

    -- 2) C_UnitAuras player aura by spellID
    if C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then
            local stacks = aura.applications or aura.stacks or aura.charges
            if aura.expirationTime and aura.expirationTime > 0 then
                return true, aura.expirationTime - now, stacks
            end
            return true, nil, stacks
        end
    end

    -- 3) Name fallback via AuraUtil (covers rare spellID swaps)
    local spellName = GetSpellNameSafe(spellId)
    if spellName and AuraUtil and type(AuraUtil.FindAuraByName) == "function" then
        local name, _, count, _, _, expirationTime = AuraUtil.FindAuraByName(spellName, "player", "HELPFUL")
        if name then
            if expirationTime and expirationTime > 0 then
                return true, expirationTime - now, count
            end
            return true, nil, count
        end
    end

    return false, nil, nil
end

---------------------------------------------------
-- Class/spec support + talent helpers
---------------------------------------------------
local function IsSupportedContext()
    if type(UnitClass) ~= "function" then return false end
    local _, classTag = UnitClass("player")
    if classTag ~= "SHAMAN" then
        return false
    end

    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return false
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return false
    end

    local specID = GetSpecializationInfo(specIndex)
    return specID == SPEC_ID_ELEMENTAL or specID == SPEC_ID_ENHANCEMENT
end

local function IsTherazanesResilienceActive()
    if type(IsPlayerSpell) == "function" and IsPlayerSpell(SPELL_EARTH_SHIELD) then
        return true
    end
    if type(IsSpellKnown) == "function" and IsSpellKnown(SPELL_EARTH_SHIELD) then
        return true
    end
    return false
end

---------------------------------------------------
-- Weapon enchants (imbues)
---------------------------------------------------
local function GetWeaponEnchantRemaining()
    local mh, mhExp, _, oh, ohExp = GetWeaponEnchantInfo()

    local mhRemain, ohRemain = nil, nil

    -- mhExp/ohExp are milliseconds remaining.
    -- They can briefly be 0 during transitions; treat 0 as "unknown" not "expiring".
    if mh and mhExp and mhExp > 0 then
        mhRemain = mhExp / 1000
    end
    if oh and ohExp and ohExp > 0 then
        ohRemain = ohExp / 1000
    end

    local readable = (mh ~= nil and oh ~= nil)
    return mh, mhRemain, oh, ohRemain, readable
end

local function FormatSeconds(s)
    s = tonumber(s)
    if not s or s <= 0 then return "" end
    if s >= 60 then
        return string.format("%dm", math.floor(s / 60))
    else
        return string.format("%ds", math.floor(s + 0.5))
    end
end

---------------------------------------------------
-- Main bar border/shadow
---------------------------------------------------
local function EnsureBarBorder()
    if MW._barBorder then return end

    local shadow = CreateFrame("Frame", nil, MW, BackdropTemplateMixin and "BackdropTemplate" or nil)
    shadow:SetFrameLevel(MW:GetFrameLevel() - 1)
    shadow:Hide()

    local border = CreateFrame("Frame", nil, MW, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetFrameLevel(MW:GetFrameLevel() + 5)
    border:Hide()

    MW._barShadow = shadow
    MW._barBorder = border
end

local function ApplyBarBorderStyle()
    EnsureBarBorder()
    local db = MaelstromTrackerDB
    if not db then return end

    if db.borderEnabled then
        local pad = tonumber(db.borderPadding) or 0
        local thick = tonumber(db.borderThickness) or 1
        if thick < 1 then thick = 1 end

        MW._barBorder:ClearAllPoints()
        MW._barBorder:SetPoint("TOPLEFT", MW, "TOPLEFT", -pad, pad)
        MW._barBorder:SetPoint("BOTTOMRIGHT", MW, "BOTTOMRIGHT", pad, -pad)

        MW._barBorder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = thick,
            insets = { left = thick, right = thick, top = thick, bottom = thick },
        })

        local bc = db.borderColor
        MW._barBorder:SetBackdropColor(0, 0, 0, 0)
        MW._barBorder:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        MW._barBorder:Show()
    else
        MW._barBorder:Hide()
    end

    if db.shadowEnabled then
        local size = tonumber(db.shadowSize) or 0
        if size < 0 then size = 0 end

        MW._barShadow:ClearAllPoints()
        MW._barShadow:SetPoint("TOPLEFT", MW, "TOPLEFT", -size, size)
        MW._barShadow:SetPoint("BOTTOMRIGHT", MW, "BOTTOMRIGHT", size, -size)

        MW._barShadow:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })

        local sc = db.shadowColor
        MW._barShadow:SetBackdropColor(sc[1], sc[2], sc[3], sc[4] or 0.6)
        MW._barShadow:SetBackdropBorderColor(0, 0, 0, 0)
        MW._barShadow:Show()
    else
        MW._barShadow:Hide()
    end
end

---------------------------------------------------
-- Main bar unlock overlay
---------------------------------------------------
local function EnsureUnlockBorder()
    if MW._unlockBorder then return end

    local border = CreateFrame("Frame", nil, MW, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints(MW)
    border:SetFrameLevel(MW:GetFrameLevel() + 20)
    border:Hide()

    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropColor(0, 0, 0, 0.20)
    border:SetBackdropBorderColor(1, 1, 1, 0.85)

    local label = border:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", border, "CENTER", 0, 0)
    label:SetText("Drag")
    label:SetTextColor(1, 1, 1, 0.85)

    MW._unlockBorder = border
end

local function ApplyLockVisual()
    EnsureUnlockBorder()
    local db = MaelstromTrackerDB
    if not db then return end
    if db.locked then MW._unlockBorder:Hide() else MW._unlockBorder:Show() end
end

---------------------------------------------------
-- Setup main bar frame
---------------------------------------------------
MW:SetSize(defaults.width, defaults.height)
MW:SetPoint(defaults.point, UIParent, defaults.point, defaults.x, defaults.y)

MW:SetMovable(true)
MW:EnableMouse(true)
MW:RegisterForDrag("LeftButton")
MW:SetClampedToScreen(true)

MW:SetScript("OnDragStart", function(self)
    if MaelstromTrackerDB and not MaelstromTrackerDB.locked then
        self:StartMoving()
    end
end)

MW:SetScript("OnDragStop", function(self)
    if not (MaelstromTrackerDB and not MaelstromTrackerDB.locked) then return end
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    if point then
        MaelstromTrackerDB.point = point
        MaelstromTrackerDB.x = x
        MaelstromTrackerDB.y = y
    end
end)

---------------------------------------------------
-- Segments
---------------------------------------------------
local function CreateSegments()
    if MW.segments then return end
    MW.segments = {}

    for i = 1, SEGMENTS do
        local t = MW:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        MW.segments[i] = t
    end
end

local function LayoutSegments()
    local db = MaelstromTrackerDB
    MW:SetSize(db.width, db.height)
    MW:ClearAllPoints()
    MW:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 0, db.y or -150)

    local segmentWidth = db.width / SEGMENTS
    for i = 1, SEGMENTS do
        local bar = MW.segments[i]
        bar:ClearAllPoints()
        bar:SetSize(segmentWidth - 2, db.height)
        bar:SetPoint("LEFT", MW, "LEFT", (i - 1) * segmentWidth, 0)
    end

    ApplyBarBorderStyle()
end

---------------------------------------------------
-- Stack Text
---------------------------------------------------
local function EnsureStackText()
    if MW._text then return end
    local fs = MW:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER", MW, "CENTER", 0, 0)
    fs:SetText("")
    MW._text = fs
end

---------------------------------------------------
-- Glow (custom outline pulse)
---------------------------------------------------
MW._glowing = nil
MW._outline = nil
MW._outlineAnim = nil

local function EnsureOutlineGlow()
    if MW._outline then return end

    local f = CreateFrame("Frame", nil, MW)
    f:SetAllPoints(MW)
    f:SetFrameLevel(MW:GetFrameLevel() + 30)
    f:Hide()

    local thickness = 4
    local pad = 2

    local function Edge()
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("ADD")
        t:SetVertexColor(1.0, 0.82, 0.0, 1.0)
        return t
    end

    local top = Edge()
    top:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, pad)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", pad, pad)
    top:SetHeight(thickness)

    local bottom = Edge()
    bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -pad, -pad)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad, -pad)
    bottom:SetHeight(thickness)

    local left = Edge()
    left:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, pad)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -pad, -pad)
    left:SetWidth(thickness)

    local right = Edge()
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", pad, pad)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad, -pad)
    right:SetWidth(thickness)

    local wash = f:CreateTexture(nil, "BACKGROUND")
    wash:SetTexture("Interface\\Buttons\\WHITE8x8")
    wash:SetAllPoints(f)
    wash:SetBlendMode("ADD")
    wash:SetVertexColor(1.0, 0.82, 0.0, 1.0)

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.10)
    a1:SetToAlpha(0.55)
    a1:SetDuration(0.45)
    a1:SetOrder(1)

    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.55)
    a2:SetToAlpha(0.10)
    a2:SetDuration(0.45)
    a2:SetOrder(2)

    MW._outline = f
    MW._outlineAnim = ag
end

local function SetGlow(enable)
    EnsureOutlineGlow()
    if enable then
        if MW._glowing then return end
        MW._glowing = true
        MW._outline:Show()
        if not MW._outlineAnim:IsPlaying() then MW._outlineAnim:Play() end
    else
        if not MW._glowing then return end
        MW._glowing = nil
        if MW._outlineAnim:IsPlaying() then MW._outlineAnim:Stop() end
        MW._outline:Hide()
    end
end

---------------------------------------------------
-- Combat visibility for main bar
---------------------------------------------------
local function ApplyCombatVisibility()
    local db = MaelstromTrackerDB
    if not db then return end
    if not IsSupportedContext() then
        MW:Hide()
        SetGlow(false)
        return
    end
    if db.onlyInCombat then
        if (type(InCombatLockdown) == "function") and InCombatLockdown() then
            MW:Show()
        else
            MW:Hide()
            SetGlow(false)
        end
    else
        MW:Show()
    end
end

---------------------------------------------------
-- Maelstrom stacks
---------------------------------------------------
local function GetMaelstromStacks()
    local found, _, stacks = GetPlayerAuraStatus(SPELL_ID)
    if not found then return 0 end
    return tonumber(stacks) or 0
end

local function GetActiveColor(db, count)
    if count <= 0 then return db.colorZero end
    if count <= 5 then return db.colorBlue end
    if count <= 9 then return db.colorOrange end
    return db.colorRed
end

---------------------------------------------------
-- Weapon Imbuements tracker frame
---------------------------------------------------
local Imbue = CreateFrame("Frame", "MaelstromTrackerImbueFrame", UIParent)
Imbue:SetFrameStrata("MEDIUM")
Imbue:SetFrameLevel(5)
Imbue:Hide()
Imbue._icons = {}
Imbue._state = {
    lastGoodReadTime = 0,
    stateTrusted = false,
    untrustedUntil = 0,
    cachedWarnings = {},
}

Imbue:SetMovable(true)
Imbue:EnableMouse(true)
Imbue:RegisterForDrag("LeftButton")
Imbue:SetClampedToScreen(true)

local function EnsureImbueState()
    if not Imbue._state then
        Imbue._state = {}
    end
    local s = Imbue._state
    if type(s.cachedWarnings) ~= "table" then
        s.cachedWarnings = {}
    end
    if type(s.lastGoodReadTime) ~= "number" then s.lastGoodReadTime = 0 end
    if type(s.untrustedUntil) ~= "number" then s.untrustedUntil = 0 end
    if s.stateTrusted ~= true then s.stateTrusted = false end
    return s
end

local function HideAllImbueIcons()
    for _, icon in pairs(Imbue._icons) do
        icon:Hide()
    end
end

local function ResetImbueRuntimeState()
    local state = EnsureImbueState()
    state.stateTrusted = false
    state.untrustedUntil = 0
    state.lastGoodReadTime = 0
    state.cachedWarnings = {}
    Imbue._bad = { wf = 0, ft = 0, ls = 0, es = 0 }
    HideAllImbueIcons()
end

local function MarkImbueStateUntrusted()
    local db = MaelstromTrackerDB
    local grace = (db and tonumber(db.imbueTrustGraceSeconds)) or defaults.imbueTrustGraceSeconds
    if grace < 0 then grace = 0 end
    local state = EnsureImbueState()
    state.stateTrusted = false
    local untilTime = GetTime() + grace
    if untilTime > state.untrustedUntil then
        state.untrustedUntil = untilTime
    end
end

local function IsImbueStateTrusted()
    local state = EnsureImbueState()
    if state.stateTrusted ~= true then return false end
    return (GetTime() >= (state.untrustedUntil or 0))
end

local function EnsureImbueUnlockOverlay()
    if Imbue._unlock then return end

    local border = CreateFrame("Frame", nil, Imbue, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints(Imbue)
    border:SetFrameLevel(Imbue:GetFrameLevel() + 20)
    border:Hide()

    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropColor(0, 0, 0, 0.20)
    border:SetBackdropBorderColor(1, 1, 1, 0.85)

    local label = border:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", border, "CENTER", 0, 0)
    label:SetText("Drag")
    label:SetTextColor(1, 1, 1, 0.85)

    Imbue._unlock = border
end

local function ApplyImbueLockVisual()
    EnsureImbueUnlockOverlay()
    local db = MaelstromTrackerDB
    if not db then return end
    if db.imbueLocked then Imbue._unlock:Hide() else Imbue._unlock:Show() end
end

Imbue:SetScript("OnDragStart", function(self)
    if MaelstromTrackerDB and not MaelstromTrackerDB.imbueLocked then
        self._isDragging = true
        self:StartMoving()
    end
end)

Imbue:SetScript("OnDragStop", function(self)
    if not (MaelstromTrackerDB and not MaelstromTrackerDB.imbueLocked) then
        self._isDragging = false
        return
    end
    self:StopMovingOrSizing()
    self._isDragging = false
    local point, _, _, x, y = self:GetPoint()
    if point then
        MaelstromTrackerDB.imbuePoint = point
        MaelstromTrackerDB.imbueX = x
        MaelstromTrackerDB.imbueY = y
    end
end)

local function CreateImbueIcon(parent, spellId)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(GetSpellIcon(spellId))

    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(f)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetAlpha(0.8)

    local warn = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warn:SetPoint("CENTER", f, "CENTER", 0, 0)
    warn:SetText("REB UFF")
    warn:SetTextColor(1, 0.2, 0.2, 1)
    warn:SetShadowOffset(1, -1)
    warn:SetShadowColor(0, 0, 0, 0.9)

    local timeLeft = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeLeft:SetPoint("BOTTOM", f, "BOTTOM", 0, -1)
    timeLeft:SetText("")
    timeLeft:SetTextColor(1, 1, 1, 1)
    timeLeft:SetShadowOffset(1, -1)
    timeLeft:SetShadowColor(0, 0, 0, 0.9)

    f._warn = warn
    f._time = timeLeft

    f:Hide()
    return f
end

local function EnsureImbueUI()
    if Imbue._ready then return end
    Imbue._ready = true
    Imbue._icons.windfury = CreateImbueIcon(Imbue, SPELL_WINDFURY)
    Imbue._icons.flametongue = CreateImbueIcon(Imbue, SPELL_FLAMETONGUE)
    Imbue._icons.lshield = CreateImbueIcon(Imbue, SPELL_LSHIELD)
    Imbue._icons.eshield = CreateImbueIcon(Imbue, SPELL_EARTH_SHIELD)
    Imbue._bad = { wf = 0, ft = 0, ls = 0, es = 0 }
    EnsureImbueUnlockOverlay()
end

local function IsInstinctiveImbuementsActive()
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(SPELL_INSTINCTIVE_IMBUEMENTS) == true
    end
    if type(IsSpellKnown) == "function" then
        return IsSpellKnown(SPELL_INSTINCTIVE_IMBUEMENTS) == true
    end
    return false
end

local function IsSanctuaryZone()
    if type(GetZonePVPInfo) ~= "function" then return false end
    return GetZonePVPInfo() == "sanctuary"
end

local function IsMythicPlusActive()
    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
        return C_ChallengeMode.IsChallengeModeActive() == true
    end
    return false
end

local function ShouldRunImbueUpdates()
    local db = MaelstromTrackerDB
    if not db or not db.imbueTrackerEnabled then return false end
    if not IsSupportedContext() then return false end

    -- Aura APIs for Lightning Shield can be restricted in combat; never query in combat.
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    if db.imbueHideInSanctuary and IsSanctuaryZone() then
        return false
    end

    if IsMythicPlusActive() then
        return false
    end

    return true
end

-- Layout only when settings/talent state changes (NOT from ticker)
local function LayoutImbueFrame(force)
    EnsureImbueUI()
    local db = MaelstromTrackerDB
    if not db then return end
    if Imbue._isDragging then return end
    if not IsSupportedContext() then
        Imbue:Hide()
        return
    end

    local size = db.imbueIconSize or 28
    local gap = 6
    local instinctive = IsInstinctiveImbuementsActive()
    local needsEarthShield = (not instinctive) and IsTherazanesResilienceActive()

    local key = table.concat({
        tostring(size),
        tostring(db.imbuePoint),
        tostring(db.imbueX),
        tostring(db.imbueY),
        instinctive and "1" or "0",
        needsEarthShield and "1" or "0",
    }, ":")

    if not force and Imbue._layoutKey == key then
        return
    end
    Imbue._layoutKey = key

    Imbue:ClearAllPoints()
    Imbue:SetPoint(db.imbuePoint or "CENTER", UIParent, db.imbuePoint or "CENTER", db.imbueX or 0, db.imbueY or 0)

    local wf = Imbue._icons.windfury
    local ft = Imbue._icons.flametongue
    local ls = Imbue._icons.lshield
    local es = Imbue._icons.eshield

    wf:SetSize(size, size)
    ft:SetSize(size, size)
    ls:SetSize(size, size)
    es:SetSize(size, size)

    wf:ClearAllPoints()
    ft:ClearAllPoints()
    ls:ClearAllPoints()
    es:ClearAllPoints()

    if instinctive then
        Imbue:SetSize(size, size)
        ls:SetPoint("CENTER", Imbue, "CENTER", 0, 0)
        es:Hide()
    else
        local iconCount = needsEarthShield and 4 or 3
        Imbue:SetSize((size * iconCount) + (gap * (iconCount - 1)), size)
        ls:SetPoint("LEFT", Imbue, "LEFT", 0, 0)
        wf:SetPoint("LEFT", ls, "RIGHT", gap, 0)
        ft:SetPoint("LEFT", wf, "RIGHT", gap, 0)
        if needsEarthShield then
            es:SetPoint("LEFT", ft, "RIGHT", gap, 0)
        else
            es:Hide()
        end
    end

    ApplyImbueLockVisual()
end

local function UpdateImbueVisibility()
    local db = MaelstromTrackerDB
    if not db then return false end

    if not db.imbueTrackerEnabled or not IsSupportedContext() then
        Imbue:Hide()
        return false
    end

    -- Never show / evaluate in combat (Lightning Shield aura can be restricted)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Imbue:Hide()
        return false
    end

    -- Optional: hide in sanctuary areas
    if db.imbueHideInSanctuary and IsSanctuaryZone() then
        Imbue:Hide()
        return false
    end

    if IsMythicPlusActive() then
        Imbue:Hide()
        return false
    end

    Imbue:Show()
    return true
end

-- WARNING ONLY: hide icons completely if no warning needed
local function UpdateImbueTracker_WarningOnly()
    EnsureImbueUI()
    local db = MaelstromTrackerDB
    if not db then return end
    if not UpdateImbueVisibility() then return end

    local warnThreshold = tonumber(db.imbueWarnSeconds) or 60
    if warnThreshold < 1 then warnThreshold = 60 end

    local wf = Imbue._icons.windfury
    local ft = Imbue._icons.flametongue
    local ls = Imbue._icons.lshield
    local es = Imbue._icons.eshield
    local state = EnsureImbueState()

    local function SetIconState(iconFrame, missing, remain)
        iconFrame:Show()
        if missing then
            iconFrame._warn:Show()
            iconFrame._time:SetText("")
            iconFrame._time:Hide()
        else
            iconFrame._warn:Hide()
            iconFrame._time:SetText(remain and remain > 0 and FormatSeconds(remain) or "")
            iconFrame._time:SetShown(remain and remain > 0)
        end
    end

    local function HideIcons()
        wf:Hide(); ft:Hide(); ls:Hide(); es:Hide()
    end

    local instinctive = IsInstinctiveImbuementsActive()
    local needsEarthShield = (not instinctive) and IsTherazanesResilienceActive()

    Imbue._bad = Imbue._bad or { wf = 0, ft = 0, ls = 0, es = 0 }

    local function DebouncedShow(key, needsNow)
        if needsNow then
            Imbue._bad[key] = (Imbue._bad[key] or 0) + 1
        else
            Imbue._bad[key] = 0
        end
        return (Imbue._bad[key] or 0) >= 2
    end

    local function CacheWarning(key, show, missing, remain)
        state.cachedWarnings[key] = {
            show = (show == true),
            missing = (missing == true),
            remain = remain,
        }
    end

    local function RenderCachedWarnings()
        HideIcons()
        local dataLS = state.cachedWarnings.ls
        if dataLS and dataLS.show then
            SetIconState(ls, dataLS.missing, dataLS.remain)
        end
        if not instinctive then
            local dataWF = state.cachedWarnings.wf
            if dataWF and dataWF.show then
                SetIconState(wf, dataWF.missing, dataWF.remain)
            end
            local dataFT = state.cachedWarnings.ft
            if dataFT and dataFT.show then
                SetIconState(ft, dataFT.missing, dataFT.remain)
            end
            if needsEarthShield then
                local dataES = state.cachedWarnings.es
                if dataES and dataES.show then
                    SetIconState(es, dataES.missing, dataES.remain)
                end
            end
        end
    end

    local now = GetTime()
    local inGraceWindow = now < (state.untrustedUntil or 0)
    local snapshot = nil
    local readOK = false

    if not inGraceWindow then
        snapshot = {}
        snapshot.instinctive = instinctive
        snapshot.needsEarthShield = needsEarthShield
        snapshot.lsFound, snapshot.lsRemain = GetPlayerAuraStatus(SPELL_LSHIELD)

        if instinctive then
            readOK = true
        else
            snapshot.hasMH, snapshot.mhRemain, snapshot.hasOH, snapshot.ohRemain, snapshot.weaponReadable = GetWeaponEnchantRemaining()
            readOK = snapshot.weaponReadable == true
            if needsEarthShield then
                snapshot.esFound, snapshot.esRemain = GetPlayerAuraStatus(SPELL_EARTH_SHIELD)
            end
        end
    end

    if readOK and snapshot then
        state.stateTrusted = true
        state.lastGoodReadTime = now

        if snapshot.instinctive then
            local lsMissing = (not snapshot.lsFound)
            local lsShow = DebouncedShow("ls", lsMissing)
            CacheWarning("ls", lsShow, lsMissing, nil)
            CacheWarning("wf", false)
            CacheWarning("ft", false)
            CacheWarning("es", false)
            Imbue._bad.wf = 0
            Imbue._bad.ft = 0
            Imbue._bad.es = 0
        else
            local lsMissing = (not snapshot.lsFound)
            local lsLow = (snapshot.lsRemain ~= nil and snapshot.lsRemain < warnThreshold)
            local lsNeeds = lsMissing or lsLow
            local lsShow = DebouncedShow("ls", lsNeeds)
            CacheWarning("ls", lsShow, lsMissing, snapshot.lsRemain)

            local wfMissing = (not snapshot.hasMH)
            local wfLow = (snapshot.mhRemain ~= nil and snapshot.mhRemain < warnThreshold)
            local wfNeeds = wfMissing or wfLow
            local wfShow = DebouncedShow("wf", wfNeeds)
            CacheWarning("wf", wfShow, wfMissing, snapshot.mhRemain)

            local ftMissing = (not snapshot.hasOH)
            local ftLow = (snapshot.ohRemain ~= nil and snapshot.ohRemain < warnThreshold)
            local ftNeeds = ftMissing or ftLow
            local ftShow = DebouncedShow("ft", ftNeeds)
            CacheWarning("ft", ftShow, ftMissing, snapshot.ohRemain)

            if snapshot.needsEarthShield then
                local esMissing = (not snapshot.esFound)
                local esShow = DebouncedShow("es", esMissing)
                CacheWarning("es", esShow, esMissing, nil)
            else
                CacheWarning("es", false)
                Imbue._bad.es = 0
            end
        end
    end

    if not IsImbueStateTrusted() then
        if db.imbueHideWhenUntrusted ~= false then
            HideIcons()
            return
        end
        RenderCachedWarnings()
        return
    end

    RenderCachedWarnings()
end

---------------------------------------------------
-- Update main bar
---------------------------------------------------
local function UpdateBarDisplay()
    local db = MaelstromTrackerDB
    if not db then return end
    if not IsSupportedContext() then
        MW:Hide()
        SetGlow(false)
        Imbue:Hide()
        ResetImbueRuntimeState()
        return
    end

    ApplyLockVisual()
    ApplyCombatVisibility()
    ApplyBarBorderStyle()

    if not MW:IsShown() then
        return
    end

    local count = GetMaelstromStacks()
    if count < 0 then count = 0 end
    if count > MAX_STACKS then count = MAX_STACKS end

    local active = GetActiveColor(db, count)
    local zero = db.colorZero
    local filled = math.min(count, SEGMENTS)

    for i = 1, SEGMENTS do
        local bar = MW.segments[i]
        bar:Show()
        if count == 0 then
            bar:SetVertexColor(zero[1], zero[2], zero[3])
            bar:SetAlpha(1.0)
        else
            if i <= filled then
                bar:SetVertexColor(active[1], active[2], active[3])
                bar:SetAlpha(1.0)
            else
                bar:SetVertexColor(zero[1], zero[2], zero[3])
                bar:SetAlpha(0.35)
            end
        end
    end

    EnsureStackText()
    if db.showStackText then
        MW._text:SetText(tostring(count))
        local tc = db.textColor or {1,1,1,1}
        local a = tc[4] or 1
        if a <= 0.02 then a = 1 end
        MW._text:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, a)
        MW._text:Show()
    else
        MW._text:Hide()
    end

    if db.glowAtTen and count >= 10 then
        SetGlow(true)
    else
        SetGlow(false)
    end
end

---------------------------------------------------
-- Public helpers for Options.lua
---------------------------------------------------
function MW:Refresh()
    if not MaelstromTrackerDB then return end
    if not IsSupportedContext() then
        MW:Hide()
        SetGlow(false)
        Imbue:Hide()
        ResetImbueRuntimeState()
        return
    end
    LayoutSegments()
    ApplyLockVisual()
    LayoutImbueFrame(true)
    ApplyImbueLockVisual()
    UpdateBarDisplay()
    if ShouldRunImbueUpdates() then
        UpdateImbueTracker_WarningOnly()
    else
        Imbue:Hide()
    end
end

function MW:ForceUpdate()
    if not IsSupportedContext() then
        MW:Hide()
        SetGlow(false)
        Imbue:Hide()
        ResetImbueRuntimeState()
        return
    end
    UpdateBarDisplay()
    if ShouldRunImbueUpdates() then
        UpdateImbueTracker_WarningOnly()
    end
end

---------------------------------------------------
-- Ticker (imbue warnings only; NO layout/SetPoint here)
---------------------------------------------------
local function EnsureImbueTicker()
    if Imbue._tickerSet then return end
    Imbue._tickerSet = true
    Imbue._elapsed = 0

    Imbue:SetScript("OnUpdate", function(self, elapsed)
        if self._isDragging then return end

        self._elapsed = (self._elapsed or 0) + (elapsed or 0)
        if self._elapsed < 0.25 then return end
        self._elapsed = 0

        if not IsSupportedContext() then
            MW:Hide()
            SetGlow(false)
            self:Hide()
            ResetImbueRuntimeState()
            return
        end

        if not ShouldRunImbueUpdates() then
            if Imbue and Imbue:IsShown() then Imbue:Hide() end
            return
        end

        UpdateImbueTracker_WarningOnly()
    end)
end

---------------------------------------------------
-- Events
---------------------------------------------------
MW:RegisterEvent("PLAYER_LOGIN")
MW:RegisterEvent("PLAYER_ENTERING_WORLD")
MW:RegisterEvent("PLAYER_REGEN_DISABLED")
MW:RegisterEvent("PLAYER_REGEN_ENABLED")
MW:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
MW:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
MW:RegisterEvent("SPELLS_CHANGED")
MW:RegisterEvent("TRAIT_CONFIG_UPDATED")
MW:RegisterEvent("ZONE_CHANGED")
MW:RegisterEvent("ZONE_CHANGED_NEW_AREA")
MW:RegisterEvent("ZONE_CHANGED_INDOORS")
MW:RegisterUnitEvent("UNIT_AURA", "player") -- if UNIT_AURA exists; harmless if it does

MW:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        InitDB()
        CreateSegments()
        EnsureImbueUI()
        MarkImbueStateUntrusted()
        LayoutSegments()
        LayoutImbueFrame(true)
        EnsureImbueTicker()
        UpdateBarDisplay()
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        MarkImbueStateUntrusted()
        UpdateBarDisplay()
        LayoutImbueFrame(false)
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        MarkImbueStateUntrusted()
        -- reset debounce on combat transitions (prevents latching due to transient reads)
        if Imbue and Imbue._bad then
            Imbue._bad.wf, Imbue._bad.ft, Imbue._bad.ls, Imbue._bad.es = 0, 0, 0, 0
        end
        UpdateBarDisplay()
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if unit and unit ~= "player" then return end
        MarkImbueStateUntrusted()
        LayoutImbueFrame(true)
        UpdateBarDisplay()
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        LayoutImbueFrame(true)
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        MarkImbueStateUntrusted()
        LayoutImbueFrame(true)
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif (event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS") then
        MarkImbueStateUntrusted()
        -- Sanctuary suppression / zone changes
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        else
            Imbue:Hide()
        end

    elseif event == "UNIT_AURA" and unit == "player" then
        UpdateBarDisplay()
        if ShouldRunImbueUpdates() then
            UpdateImbueTracker_WarningOnly()
        end
    end
end)
