local ADDON_NAME = ...

local DONATION_URL = "https://www.paypal.com/donate/?business=faney%40live.com&no_recurring=0&currency_code=USD"

local DEFAULTS = {
    enabled = true,
    opacity = 0,
    minimap = {
        hide = false,
        angle = 225,
    },
}

local TARGET_ATLASES = {
    ["UI-HUD-RotationHelper-Inactive-2x"] = true,
    ["UI-HUD-RotationHelper-Active-2x"] = true,
}

local hooked = setmetatable({}, { __mode = "k" })
local managed = setmetatable({}, { __mode = "k" })
local optionsCategory
local optionsPanel
local minimapButton
local OpenOptions
local ADDON_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or GetAddOnMetadata(ADDON_NAME, "Version") or "1.2.0"

local function IsEllesmereLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("EllesmereUI")
    end
    return IsAddOnLoaded and IsAddOnLoaded("EllesmereUI") or false
end

local function DetectedUIName()
    return IsEllesmereLoaded() and "EllesmereUI" or "Blizzard UI"
end

local function PrintStatus(message)
    print("|cff33ff99HBAAE:|r " .. message)
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function LoadDatabase()
    HBAAE_DB = HBAAE_DB or {}

    if HBAAE_DB.enabled == nil then
        HBAAE_DB.enabled = DEFAULTS.enabled
    end

    if HBAAE_DB.opacity == nil then
        HBAAE_DB.opacity = DEFAULTS.opacity
    end

    HBAAE_DB.opacity = Clamp(HBAAE_DB.opacity, 0, 1)

    HBAAE_DB.minimap = HBAAE_DB.minimap or {}
    if HBAAE_DB.minimap.hide == nil then
        HBAAE_DB.minimap.hide = DEFAULTS.minimap.hide
    end
    if HBAAE_DB.minimap.angle == nil then
        HBAAE_DB.minimap.angle = DEFAULTS.minimap.angle
    end
    HBAAE_DB.minimap.angle = tonumber(HBAAE_DB.minimap.angle) or DEFAULTS.minimap.angle
end

local function CurrentAlpha()
    if not HBAAE_DB or not HBAAE_DB.enabled then
        return 1
    end

    return Clamp(HBAAE_DB.opacity, 0, 1)
end

local function ApplyState(object)
    if not object then return end

    managed[object] = true
    local alpha = CurrentAlpha()

    if object.SetAlpha then
        pcall(object.SetAlpha, object, alpha)
    end

    if HBAAE_DB and HBAAE_DB.enabled and alpha <= 0 then
        if object.Hide then
            pcall(object.Hide, object)
        end
    else
        if object.Show then
            pcall(object.Show, object)
        end
    end

    if object.HookScript and not hooked[object] then
        hooked[object] = true

        object:HookScript("OnShow", function(self)
            if not HBAAE_DB or not HBAAE_DB.enabled then return end

            local wantedAlpha = CurrentAlpha()

            if self.SetAlpha then
                self:SetAlpha(wantedAlpha)
            end

            if wantedAlpha <= 0 then
                C_Timer.After(0, function()
                    if HBAAE_DB and HBAAE_DB.enabled and CurrentAlpha() <= 0 and self.Hide then
                        self:Hide()
                    end
                end)
            end
        end)
    end
end

local function RestoreAll()
    for object in pairs(managed) do
        if object then
            if object.SetAlpha then
                pcall(object.SetAlpha, object, 1)
            end
            if object.Show then
                pcall(object.Show, object)
            end
        end
    end
end

-- Blizzard's default action buttons attach the helper directly to each button.
local function ProcessBlizzardButton(button)
    if not button then return 0 end

    local frame = button.AssistedCombatRotationFrame
    if not frame then return 0 end

    local count = 0

    if frame.InactiveTexture then
        ApplyState(frame.InactiveTexture)
        count = count + 1
    end

    if frame.ActiveFrame then
        ApplyState(frame.ActiveFrame)
        count = count + 1
    end

    if frame.ActiveTexture then
        ApplyState(frame.ActiveTexture)
        count = count + 1
    end

    return count
end

local buttonFamilies = {
    { "ActionButton", 12 },
    { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 },
    { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 },
    { "MultiBar7Button", 12 },
    { "MultiBar8Button", 12 },
    { "MultiBar9Button", 12 },
    { "MultiBar10Button", 12 },
    { "MultiBar11Button", 12 },
    { "MultiBar12Button", 12 },
    { "OverrideActionBarButton", 6 },
}

local function ScanBlizzard()
    local found = 0

    for _, family in ipairs(buttonFamilies) do
        local prefix, amount = family[1], family[2]

        for index = 1, amount do
            found = found + ProcessBlizzardButton(_G[prefix .. index])
        end
    end

    return found
end

-- EllesmereUI creates a separate spinner child using a RotationHelper atlas.
local function TextureUsesTargetAtlas(region)
    if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then
        return false
    end

    if not region.GetAtlas then return false end

    local atlas = region:GetAtlas()
    return atlas and TARGET_ATLASES[atlas] or false
end

local function ProcessEllesmereFrame(frame)
    if not frame or not frame.GetRegions then return 0 end

    local found = 0
    local regions = { frame:GetRegions() }

    for _, region in ipairs(regions) do
        if TextureUsesTargetAtlas(region) then
            ApplyState(region)
            ApplyState(frame)
            found = found + 1
        end
    end

    return found
end

local function ScanEllesmere()
    local found = 0

    for index = 1, 300 do
        local button = _G["EABButton" .. index]

        if button then
            found = found + ProcessEllesmereFrame(button)

            if button.GetChildren then
                local children = { button:GetChildren() }

                for _, child in ipairs(children) do
                    found = found + ProcessEllesmereFrame(child)

                    if child.GetChildren then
                        local grandchildren = { child:GetChildren() }

                        for _, grandchild in ipairs(grandchildren) do
                            found = found + ProcessEllesmereFrame(grandchild)
                        end
                    end
                end
            end
        end
    end

    return found
end

local function ScanAll()
    if not HBAAE_DB or not HBAAE_DB.enabled then return 0 end

    local found = 0
    found = found + ScanBlizzard()
    found = found + ScanEllesmere()
    return found
end

local function SetEnabled(enabled)
    HBAAE_DB.enabled = not not enabled

    if HBAAE_DB.enabled then
        ScanAll()
    else
        RestoreAll()
    end
end

local function SetOpacity(value)
    HBAAE_DB.opacity = Clamp(value, 0, 1)

    if HBAAE_DB.enabled then
        ScanAll()
    end
end

StaticPopupDialogs["HBAAE_DONATION_LINK"] = {
    text = "Support HBAAE development via PayPal.\n\nCopy the link below and open it in your browser:",
    button1 = OKAY,
    hasEditBox = true,
    editBoxWidth = 360,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self.EditBox:SetText(DONATION_URL)
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
}

local function OpenDonation()
    -- Use Blizzard's external-link API when available.
    if C_Browser and C_Browser.OpenExternalLink then
        local ok = pcall(C_Browser.OpenExternalLink, DONATION_URL)
        if ok then
            return
        end
    end

    StaticPopup_Show("HBAAE_DONATION_LINK")
end

local function UpdateMinimapPosition()
    if not minimapButton or not Minimap or not HBAAE_DB or not HBAAE_DB.minimap then return end

    local angle = math.rad(HBAAE_DB.minimap.angle or DEFAULTS.minimap.angle)
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function SetMinimapVisible(visible)
    HBAAE_DB.minimap.hide = not visible

    if minimapButton then
        if visible then
            minimapButton:Show()
            UpdateMinimapPosition()
        else
            minimapButton:Hide()
        end
    end
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end

    local button = CreateFrame("Button", "HBAAEMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:EnableMouseWheel(true)
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:SetClampedToScreen(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\AddOns\\HBAAE\\icon")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetSize(32, 32)
    highlight:SetPoint("CENTER")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            HBAAE_DB.minimap.angle = math.deg(math.atan2(cursorY - my, cursorX - mx))
            UpdateMinimapPosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            SetEnabled(not HBAAE_DB.enabled)
            PrintStatus(HBAAE_DB.enabled and "Enabled." or "Disabled.")
        else
            OpenOptions()
        end
    end)

    button:SetScript("OnMouseWheel", function(_, delta)
        local currentPercent = math.floor((HBAAE_DB.opacity or 0) * 100 + 0.5)
        local step = delta > 0 and 5 or -5
        local newPercent = Clamp(currentPercent + step, 0, 100)
        SetOpacity(newPercent / 100)
        PrintStatus(string.format("Assistant Arrow opacity: %d%%.", newPercent))
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Hide Assistant Arrow (HBAAE)", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Version", ADDON_VERSION, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Detected UI", DetectedUIName(), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Status", HBAAE_DB.enabled and "Enabled" or "Disabled", 0.8, 0.8, 0.8, HBAAE_DB.enabled and 0.2 or 1, HBAAE_DB.enabled and 1 or 0.2, 0.2)
        GameTooltip:AddDoubleLine("Arrow opacity", string.format("%d%%", math.floor((HBAAE_DB.opacity or 0) * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: Open settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Enable / Disable", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Mouse wheel: Adjust opacity by 5%", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Move around the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton = button
    UpdateMinimapPosition()
    SetMinimapVisible(not HBAAE_DB.minimap.hide)
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "HBAAE"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HBAAE")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Hide or fade the Single-Button Assistant arrow for Blizzard and EllesmereUI action bars.")

    local enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", 16, -70)
    enabled.Text:SetText("Enable HBAAE")

    local showMinimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    showMinimap:SetPoint("TOPLEFT", 16, -105)
    showMinimap.Text:SetText("Show minimap button")

    local opacityLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    opacityLabel:SetPoint("TOPLEFT", 20, -155)
    opacityLabel:SetText("Arrow opacity")

    local slider = CreateFrame("Slider", "HBAAEOpacitySlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 4, -20)
    slider:SetWidth(320)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    _G[slider:GetName() .. "Low"]:SetText("0%")
    _G[slider:GetName() .. "High"]:SetText("100%")

    local valueText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 18, 0)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(130, 24)
    reset:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -35)
    reset:SetText("Restore Defaults")

    local donate = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    donate:SetSize(150, 24)
    donate:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    donate:SetText("Donate via PayPal")
    donate:SetScript("OnClick", OpenDonation)

    local function Refresh()
        enabled:SetChecked(HBAAE_DB.enabled)
        showMinimap:SetChecked(not HBAAE_DB.minimap.hide)
        slider:SetValue(math.floor((HBAAE_DB.opacity or 0) * 100 + 0.5))
        slider:SetEnabled(HBAAE_DB.enabled)
        valueText:SetText(string.format("%d%%", math.floor((HBAAE_DB.opacity or 0) * 100 + 0.5)))
    end

    enabled:SetScript("OnClick", function(self)
        SetEnabled(self:GetChecked())
        Refresh()
    end)

    showMinimap:SetScript("OnClick", function(self)
        SetMinimapVisible(self:GetChecked())
    end)

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        valueText:SetText(value .. "%")

        if HBAAE_DB and HBAAE_DB.enabled then
            SetOpacity(value / 100)
        end
    end)

    reset:SetScript("OnClick", function()
        HBAAE_DB.enabled = DEFAULTS.enabled
        HBAAE_DB.opacity = DEFAULTS.opacity
        HBAAE_DB.minimap.hide = DEFAULTS.minimap.hide
        HBAAE_DB.minimap.angle = DEFAULTS.minimap.angle
        SetMinimapVisible(true)
        UpdateMinimapPosition()
        ScanAll()
        Refresh()
    end)

    panel:SetScript("OnShow", Refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, "HBAAE")
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    return panel
end

OpenOptions = function()
    if Settings and Settings.OpenToCategory and optionsCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return
    end

    if InterfaceOptionsFrame_OpenToCategory and optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
end

SLASH_HBAAE1 = "/hbaae"
SlashCmdList.HBAAE = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")

    if message == "" then
        OpenOptions()
    elseif message == "on" then
        SetEnabled(true)
        print("|cff33ff99HBAAE:|r enabled.")
    elseif message == "off" then
        SetEnabled(false)
        print("|cff33ff99HBAAE:|r disabled.")
    elseif message == "minimap" or message == "minimap show" then
        SetMinimapVisible(true)
        print("|cff33ff99HBAAE:|r minimap button shown.")
    elseif message == "minimap hide" then
        SetMinimapVisible(false)
        print("|cff33ff99HBAAE:|r minimap button hidden. Type /hbaae minimap to restore it.")
    else
        local opacity = message:match("^opacity%s+(%d+)$")

        if opacity then
            opacity = Clamp(tonumber(opacity), 0, 100)
            SetOpacity(opacity / 100)
            print(string.format("|cff33ff99HBAAE:|r opacity set to %d%%.", opacity))
        else
            print("|cff33ff99HBAAE commands:|r /hbaae, /hbaae on, /hbaae off, /hbaae opacity 0-100, /hbaae minimap, /hbaae minimap hide")
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        LoadDatabase()
        optionsPanel = CreateOptionsPanel()
        return
    end

    if event == "PLAYER_LOGIN" then
        CreateMinimapButton()
    end

    if HBAAE_DB and HBAAE_DB.enabled then
        C_Timer.After(0, ScanAll)
        C_Timer.After(0.5, ScanAll)
        C_Timer.After(2, ScanAll)
    end
end)

-- Retry while Blizzard or EllesmereUI finishes creating action buttons.
local attempts = 0
local retryTicker
retryTicker = C_Timer.NewTicker(1, function()
    attempts = attempts + 1

    if HBAAE_DB and HBAAE_DB.enabled then
        ScanAll()
    end

    if attempts >= 20 then
        retryTicker:Cancel()
    end
end)
