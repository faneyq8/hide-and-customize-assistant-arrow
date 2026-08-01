local ADDON_NAME = ...
local VERSION = "1.4.1"
local DONATION_URL = "https://www.paypal.com/donate/?business=faney%40live.com&no_recurring=0&currency_code=USD"
local SOCIAL = {
    twitch={label="Twitch", value="https://www.twitch.tv/gamerzoneq8", icon="Interface\\AddOns\\HCAA\\Social\\twitch"},
    tiktok={label="TikTok", value="https://www.tiktok.com/@gamerzoneq8", icon="Interface\\AddOns\\HCAA\\Social\\tiktok"},
    discord={label="Discord", value=".faney", icon="Interface\\AddOns\\HCAA\\Social\\discord"},
    battlenet={label="Battle.net", value="Faney#2957", icon="Interface\\AddOns\\HCAA\\Social\\battlenet"},
    github={label="GitHub", value="https://github.com/faneyq8", icon="Interface\\AddOns\\HCAA\\Social\\github"},
    donate={label="Donate", value=DONATION_URL, icon="Interface\\AddOns\\HCAA\\Social\\donate"},
}
BINDING_HEADER_HCAA = "HCAA"
BINDING_NAME_HCAA_TOGGLE = "Toggle HCAA"

local SHAPES = {
    "skull_ring", "circle", "star", "shield", "diamond", "rune", "wings",
    "flame", "lightning", "moon", "compass", "sword", "crown", "crystal",
    "sun", "void", "hexagon", "triangle", "cross", "minimal_ring",
}
local SHAPE_LABELS = {
    skull_ring="Skull Ring", circle="Circle", star="Star", shield="Shield", diamond="Diamond",
    rune="Rune", wings="Wings", flame="Flame", lightning="Lightning", moon="Moon",
    compass="Compass", sword="Sword", crown="Crown", crystal="Crystal", sun="Sun",
    void="Void", hexagon="Hexagon", triangle="Triangle", cross="Cross", minimal_ring="Minimal Ring",
}
local VALID_SHAPES = {}; for _,shape in ipairs(SHAPES) do VALID_SHAPES[shape]=true end
local LEGACY_SHAPE_MAP = {
    original="circle", thin_arrow="minimal_ring", thick_arrow="shield", modern_arrow="diamond",
    minimal_chevron="triangle", triangle="triangle", diamond="diamond", circle="circle",
    crosshair="cross", sword="sword", shield="shield", crystal="crystal", rune="rune",
    star="star", skull="skull_ring", flame="flame", lightning="lightning", holy="sun",
    shadow="void", pixel_arrow="hexagon",
}
local TARGET_ATLASES = { ["UI-HUD-RotationHelper-Inactive-2x"]=true, ["UI-HUD-RotationHelper-Active-2x"]=true }
local UI_ADDONS = { EllesmereUI="EllesmereUI", EllesmereUIActionBars="EllesmereUI Action Bars", ElvUI="ElvUI", Bartender4="Bartender4", Dominos="Dominos" }

local DEFAULT_PROFILE = {
    enabled=true, opacity=0, mode="hidden", shape="circle", colorEnabled=true, color={1,0.72,0.05,1},
    scale=1, rotation=0, offsetX=0, offsetY=0, glow=false, glowColor={1,0.78,0.05,1}, glowIntensity=.65,
    pulse=false, pulseSpeed=1.5, flashOnProc=true, fade=true, fadeDuration=0.20,
    autoCombat="none", zones={solo=true,dungeon=true,raid=true,arena=true,battleground=true},
}
local DEFAULTS = {
    schemaVersion=2, profileMode="account", minimap={hide=false,angle=225}, firstRun=true,
    profiles={account={}}, characterProfiles={}, specProfiles={}, statistics={hiddenCount=0,hiddenSeconds=0,lastStart=nil},
}

local managed = setmetatable({}, {__mode="k"})
local arrowTextures = setmetatable({}, {__mode="k"})
local original = setmetatable({}, {__mode="k"})
local hooked = setmetatable({}, {__mode="k"})
local minimapButton, configFrame, colorSwatch, shapeDropdown, RefreshConfig
local NormalizeModeForUI
local pulseTicker, hiddenTicker
local StartPulseTicker, ScanAll, ApplyCached, ScheduleScan
local scanPending=false
local runtimeStatus={count=0,blizzard=0,ellesmere=0,elvui=0,lastError=nil,lastErrorKey=nil}
local RecordScanError

local function Clamp(v,a,b) v=tonumber(v) or a if v<a then return a elseif v>b then return b end return v end
local function CopyDefaults(src,dst)
    dst=dst or {}
    for k,v in pairs(src) do
        if type(v)=="table" then dst[k]=CopyDefaults(v,type(dst[k])=="table" and dst[k] or {}) elseif dst[k]==nil then dst[k]=v end
    end
    return dst
end
local function DeepCopy(src)
    if type(src)~="table" then return src end
    local dst={}
    for k,v in pairs(src) do dst[DeepCopy(k)]=DeepCopy(v) end
    return dst
end
local function NormalizeShape(shape)
    if VALID_SHAPES[shape] then return shape end
    return LEGACY_SHAPE_MAP[shape] or "circle"
end
local function MigrateProfile(profile)
    profile=CopyDefaults(DEFAULT_PROFILE,type(profile)=="table" and profile or {})
    profile.shape=NormalizeShape(profile.shape)
    if profile.mode~="hidden" and profile.mode~="original" and profile.mode~="custom" then profile.mode="hidden" end
    profile.colorEnabled = profile.colorEnabled ~= false
    profile.opacity=Clamp(profile.opacity,0,1); profile.scale=Clamp(profile.scale,.5,2); profile.rotation=tonumber(profile.rotation) or 0
    profile.offsetX=Clamp(profile.offsetX or 0,-80,80); profile.offsetY=Clamp(profile.offsetY or 0,-80,80)
    return profile
end
local function MigrateDatabase(db)
    db=CopyDefaults(DEFAULTS,type(db)=="table" and db or {})
    db.profiles.account=MigrateProfile(db.profiles.account)
    for key,profile in pairs(db.characterProfiles) do db.characterProfiles[key]=MigrateProfile(profile) end
    for key,profile in pairs(db.specProfiles) do db.specProfiles[key]=MigrateProfile(profile) end
    db.schemaVersion=2
    return db
end
local function Print(msg) print("|cff33ff99HCAA:|r "..msg) end
local function CharacterKey() return (UnitName("player") or "Unknown").."-"..(GetRealmName() or "Realm") end
local function SpecKey() local id=GetSpecialization() return CharacterKey()..":"..tostring(id or 0) end
local function Profile()
    if not HCAA_DB then return DEFAULT_PROFILE end
    local mode=HCAA_DB.profileMode or "account"
    if mode=="character" then
        local k=CharacterKey(); HCAA_DB.characterProfiles[k]=MigrateProfile(HCAA_DB.characterProfiles[k]); return NormalizeModeForUI(HCAA_DB.characterProfiles[k])
    elseif mode=="spec" then
        local k=SpecKey(); HCAA_DB.specProfiles[k]=MigrateProfile(HCAA_DB.specProfiles[k]); return NormalizeModeForUI(HCAA_DB.specProfiles[k])
    end
    HCAA_DB.profiles.account=MigrateProfile(HCAA_DB.profiles.account)
    return NormalizeModeForUI(HCAA_DB.profiles.account)
end
local function Loaded(name) return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or (IsAddOnLoaded and IsAddOnLoaded(name)) end
local function IsEllesmereUI() return Loaded("EllesmereUI") or Loaded("EllesmereUIActionBars") end
NormalizeModeForUI = function(profile)
    if profile and IsEllesmereUI() and profile.mode=="original" then profile.mode="custom" end
    return profile
end
local function DetectedUI()
    local t={}
    for addon,label in pairs(UI_ADDONS) do if Loaded(addon) then t[#t+1]=label end end
    if #t==0 then return "Blizzard UI" end
    table.sort(t); return table.concat(t, ", ")
end
local function ZoneType()
    local inInstance,kind=IsInInstance()
    if not inInstance then return "solo" end
    if kind=="party" then return "dungeon" elseif kind=="raid" then return "raid" elseif kind=="arena" then return "arena" elseif kind=="pvp" then return "battleground" end
    return "solo"
end
local function RuleAllows(p)
    if p.zones and p.zones[ZoneType()]==false then return false end
    if p.autoCombat=="hide_in_combat" and InCombatLockdown() then return false end
    if p.autoCombat=="show_in_combat" and not InCombatLockdown() then return false end
    return true
end
local function EffectiveAlpha()
    local p=Profile()
    if not p.enabled then return 1 end
    if not RuleAllows(p) then return 0 end
    if p.mode=="hidden" then return 0 end
    return Clamp(p.opacity,0,1)
end
local function ShapePath(shape) return "Interface\\AddOns\\HCAA\\Shapes\\"..NormalizeShape(shape) end
local function Remember(obj)
    if original[obj] then return end
    local data={alpha=obj.GetAlpha and obj:GetAlpha() or 1, width=obj.GetWidth and obj:GetWidth(), height=obj.GetHeight and obj:GetHeight(), shown=obj.IsShown and obj:IsShown()}
    if obj.GetObjectType and obj:GetObjectType()=="Texture" then
        data.atlas=obj.GetAtlas and obj:GetAtlas(); data.texture=obj.GetTexture and obj:GetTexture(); data.rotation=obj.GetRotation and obj:GetRotation() or 0
        data.blendMode=obj.GetBlendMode and obj:GetBlendMode()
        if obj.GetVertexColor then data.r,data.g,data.b,data.a=obj:GetVertexColor() end
    elseif obj.GetObjectType and obj:GetObjectType()=="FontString" and obj.GetDrawLayer then
        data.layer,data.sublevel=obj:GetDrawLayer()
    end
    original[obj]=data
end
local function Restore(obj)
    local d=original[obj]; if not d or not obj then return end
    if obj.SetAlpha then pcall(obj.SetAlpha,obj,d.alpha or 1) end
    if obj.GetObjectType and obj:GetObjectType()=="Texture" then
        if d.atlas and obj.SetAtlas then pcall(obj.SetAtlas,obj,d.atlas,true) elseif d.texture and obj.SetTexture then pcall(obj.SetTexture,obj,d.texture) end
        if obj.SetVertexColor then pcall(obj.SetVertexColor,obj,d.r or 1,d.g or 1,d.b or 1,d.a or 1) end
        if obj.SetRotation then pcall(obj.SetRotation,obj,d.rotation or 0) end
        if d.blendMode and obj.SetBlendMode then pcall(obj.SetBlendMode,obj,d.blendMode) end
        if d.width and d.height and obj.SetSize then pcall(obj.SetSize,obj,d.width,d.height) end
    elseif obj.GetObjectType and obj:GetObjectType()=="FontString" and d.layer and obj.SetDrawLayer then
        pcall(obj.SetDrawLayer,obj,d.layer,d.sublevel or 0)
    end
    if d.shown==false and obj.Hide then pcall(obj.Hide,obj) elseif obj.Show then pcall(obj.Show,obj) end
end
local glowOverlays=setmetatable({}, {__mode="k"})
local customOverlays=setmetatable({}, {__mode="k"})
-- EllesmereUI builds the Assistant Arrow template on many action buttons, but only
-- one button owns the currently visible recommendation. Cache only that owner so
-- HCAA never decorates every action button.
local ellesmereOwners=setmetatable({}, {__mode="k"})
local activeEllesmereOwners=setmetatable({}, {__mode="k"})
local elvuiOwners=setmetatable({}, {__mode="k"})
local hookedElvUIButtons=setmetatable({}, {__mode="k"})
local elvuiAssistHooked=false
local visualApplyPending=false
-- Performance-safe alpha application. The old implementation created one 50 FPS
-- ticker per texture, which could reduce the game to 1 FPS when a shape was selected.
local function FadeObject(obj,target,duration)
    if not obj or not obj.SetAlpha then return end
    target=Clamp(target or 0,0,1)
    obj:SetAlpha(target)
end
local function UpdateGlow(tex,isActive,multiplier)
    local p=Profile()
    local glow=glowOverlays[tex]
    if not p.glow or p.mode~="custom" or EffectiveAlpha()<=0 then
        if glow then glow:Hide() end
        return
    end
    if not glow then
        local parent=tex.GetParent and tex:GetParent()
        if not parent or not parent.CreateTexture then return end
        -- Keep glow behind the colored frame. Drawing it above the frame mixed
        -- both RGB values into one flat color, especially with EllesmereUI.
        glow=parent:CreateTexture(nil,"OVERLAY",nil,5)
        glow:SetBlendMode("ADD")
        if glow.SetDesaturated then glow:SetDesaturated(true) end
        glowOverlays[tex]=glow
    end
    local c=p.glowColor or {1,.78,.05,1}
    local tw=(tex.GetWidth and tex:GetWidth()) or 64
    local th=(tex.GetHeight and tex:GetHeight()) or 64
    glow:ClearAllPoints()
    glow:SetPoint("CENTER",tex,"CENTER",0,0)
    glow:SetSize(tw+14,th+14)
    glow:SetTexture(ShapePath(p.shape))
    if glow.SetDesaturated then glow:SetDesaturated(true) end
    glow:SetVertexColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1)
    if glow.SetRotation then glow:SetRotation(math.rad(tonumber(p.rotation) or 0)) end
    local boost=(isActive and p.flashOnProc) and 1.35 or 1
    glow:SetAlpha(Clamp(EffectiveAlpha()*(p.glowIntensity or .65)*boost*(multiplier or 1),0,1))
    glow:Show()
end

local function HideGlowFor(tex)
    local g=glowOverlays[tex]
    if g then g:Hide() end
end

local function EnsureCustomOverlay(owner, anchorTex, isActive)
    if not owner or not owner.CreateTexture or not anchorTex then return nil end
    local p=Profile()
    local overlay=customOverlays[owner]
    if not overlay then
        overlay=owner:CreateTexture(nil,"OVERLAY",nil,6)
        overlay:SetPoint("CENTER",anchorTex,"CENTER",p.offsetX or 0,p.offsetY or 0)
        overlay:SetBlendMode("BLEND")
        if overlay.SetDesaturated then overlay:SetDesaturated(true) end
        customOverlays[owner]=overlay
    end
    overlay._hcaaAnchor=anchorTex
    local d=original[anchorTex]
    local baseW=(d and d.width) or (anchorTex.GetWidth and anchorTex:GetWidth()) or 64
    local baseH=(d and d.height) or (anchorTex.GetHeight and anchorTex:GetHeight()) or 64
    overlay._hcaaBaseW=baseW
    overlay._hcaaBaseH=baseH
    local scale=Clamp(tonumber(p.scale) or 1,.5,2)
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER",anchorTex,"CENTER",p.offsetX or 0,p.offsetY or 0)
    overlay:SetSize(baseW*scale,baseH*scale)
    overlay:SetTexture(ShapePath(p.shape))
    local useColor=p.colorEnabled~=false
    if overlay.SetDesaturated then overlay:SetDesaturated(useColor) end
    local c=useColor and (p.color or {1,1,1,1}) or {1,1,1,1}
    overlay:SetVertexColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1)
    if overlay.SetRotation then overlay:SetRotation(math.rad(tonumber(p.rotation) or 0)) end
    overlay:SetAlpha(EffectiveAlpha())
    overlay:SetShown(p.enabled and p.mode=="custom" and EffectiveAlpha()>0)
    UpdateGlow(overlay,isActive)
    return overlay
end

local function HideCustomOverlay(owner)
    local overlay=customOverlays[owner]
    if overlay then overlay:Hide(); HideGlowFor(overlay) end
end

local function ScheduleVisualApply()
    if visualApplyPending then return end
    visualApplyPending=true
    C_Timer.After(0.08,function()
        visualApplyPending=false
        if HCAA_DB then
            ApplyCached()
            if RefreshConfig then RefreshConfig() end
        end
    end)
end

local function ApplyTextureStyle(tex,isActive)
    if not tex then return end
    Remember(tex); managed[tex]=true; arrowTextures[tex]=true
    local p=Profile(); local alpha=EffectiveAlpha()
    if p.mode=="custom" then
        -- Never turn Blizzard/Ellesmere arrow layers into custom shapes. They often
        -- contain several active/inactive textures, which caused stacked frames.
        -- A single owner overlay is rendered by EnsureCustomOverlay instead.
        Restore(tex)
        tex:Show()
        tex:SetAlpha(0)
        HideGlowFor(tex)
        return
    else
        local d=original[tex]
        if d then
            if d.atlas and tex.SetAtlas then tex:SetAtlas(d.atlas,true) elseif d.texture then tex:SetTexture(d.texture) end
            local useColor=p.colorEnabled~=false
            local c=useColor and (p.color or {1,1,1,1}) or {d.r or 1,d.g or 1,d.b or 1,d.a or 1}
            tex:SetVertexColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1)
            if tex.SetRotation then tex:SetRotation(d.rotation or 0) end
            if d.width and d.height then tex:SetSize(d.width,d.height) end
        end
    end
    -- Keep the region shown and use alpha 0 for hidden mode. This prevents Blizzard
    -- or EllesmereUI from immediately showing it again and avoids OnShow loops.
    tex:Show()
    FadeObject(tex,alpha,p.fadeDuration)
    UpdateGlow(tex,isActive)
    if not hooked[tex] and tex.HookScript then
        hooked[tex]=true; tex:HookScript("OnShow",function(self) C_Timer.After(0,function() if HCAA_DB then local ok,err=pcall(ApplyTextureStyle,self); if not ok and RecordScanError then RecordScanError("Texture OnShow",err) end end end) end)
    end
end
local function ApplyFrame(frame)
    if not frame then return end
    Remember(frame); managed[frame]=true
    local a=EffectiveAlpha(); frame:Show(); FadeObject(frame,a,Profile().fadeDuration)
end
local function ProtectReadableRegion(region)
    if (type(region)~="table" and type(region)~="userdata") or not region.GetObjectType or region:GetObjectType()~="FontString" then return end
    Remember(region); managed[region]=true
    if region.SetDrawLayer then pcall(region.SetDrawLayer,region,"OVERLAY",7) end
    if region.SetAlpha then pcall(region.SetAlpha,region,1) end
end
local function ProtectButtonText(button)
    if not button then return end
    for _,key in ipairs({"HotKey","Count","Name","Border","Flash"}) do ProtectReadableRegion(button[key]) end
    if button.GetRegions then for _,region in ipairs({button:GetRegions()}) do ProtectReadableRegion(region) end end
end
local function ProcessBlizzardButton(button)
    local f=button and button.AssistedCombatRotationFrame; if not f then return 0 end
    ProtectButtonText(button)
    local targets={}
    if f.InactiveTexture then targets[#targets+1]={f.InactiveTexture,false} end
    if f.ActiveTexture then targets[#targets+1]={f.ActiveTexture,true} end
    if f.ActiveFrame and f.ActiveFrame.GetRegions then
        for _,r in ipairs({f.ActiveFrame:GetRegions()}) do
            if r and r.GetObjectType and r:GetObjectType()=="Texture" then targets[#targets+1]={r,true} end
        end
    end
    if #targets==0 then return 0 end
    local p=Profile()
    if p.mode=="custom" then
        -- Restore and hide every Blizzard arrow layer, then render exactly one custom overlay.
        for _,entry in ipairs(targets) do
            local tex=entry[1]; Remember(tex); managed[tex]=true; arrowTextures[tex]=true
            Restore(tex); tex:Show(); tex:SetAlpha(0); HideGlowFor(tex)
        end
        if f.ActiveFrame then Remember(f.ActiveFrame); managed[f.ActiveFrame]=true; f.ActiveFrame:Show(); f.ActiveFrame:SetAlpha(1) end
        EnsureCustomOverlay(f,targets[1][1],false)
    else
        HideCustomOverlay(f)
        for _,entry in ipairs(targets) do ApplyTextureStyle(entry[1],entry[2]) end
        if f.ActiveFrame then ApplyFrame(f.ActiveFrame) end
    end
    return #targets
end
local families={{"ActionButton",12},{"MultiBarBottomLeftButton",12},{"MultiBarBottomRightButton",12},{"MultiBarRightButton",12},{"MultiBarLeftButton",12},{"MultiBar5Button",12},{"MultiBar6Button",12},{"MultiBar7Button",12},{"MultiBar8Button",12},{"MultiBar9Button",12},{"MultiBar10Button",12},{"MultiBar11Button",12},{"MultiBar12Button",12},{"OverrideActionBarButton",6}}
local function ScanBlizzard()
    local n=0
    for _,family in ipairs(families) do for i=1,family[2] do local ok,count=pcall(ProcessBlizzardButton,_G[family[1]..i]); if ok then n=n+(count or 0) elseif RecordScanError then RecordScanError("Blizzard UI button",count) end end end
    return n
end
local function TargetTexture(r)
    if not r or not r.GetObjectType or r:GetObjectType()~="Texture" or not r.GetAtlas then return false end
    local ok,atlas=pcall(r.GetAtlas,r)
    return ok and TARGET_ATLASES[atlas] or false
end
local function RegionVisible(region)
    if not region or not region.IsShown or not region.GetAlpha then return false end
    local okShown,shown=pcall(region.IsShown,region)
    local okAlpha,alpha=pcall(region.GetAlpha,region)
    if not okShown or not shown or not okAlpha or (alpha or 0)<=0.01 then return false end
    local parent=region.GetParent and region:GetParent()
    local depth=0
    while parent and depth<8 do
        if parent.IsShown then
            local ok,v=pcall(parent.IsShown,parent)
            if ok and not v then return false end
        end
        if parent.GetAlpha then
            local ok,v=pcall(parent.GetAlpha,parent)
            if ok and (v or 0)<=0.01 then return false end
        end
        parent=parent.GetParent and parent:GetParent() or nil
        depth=depth+1
    end
    return true
end

local function CollectEllesmereTargets(frame,depth,seen,out,visibleOnly)
    if not frame or seen[frame] or depth>5 then return end
    seen[frame]=true
    if frame.GetRegions then
        for _,r in ipairs({frame:GetRegions()}) do
            if TargetTexture(r) and (not visibleOnly or RegionVisible(r)) then
                out[#out+1]=r
            elseif r and r.GetObjectType and r:GetObjectType()=="FontString" then
                ProtectReadableRegion(r)
            end
        end
    end
    if frame.GetChildren then
        for _,child in ipairs({frame:GetChildren()}) do
            CollectEllesmereTargets(child,depth+1,seen,out,visibleOnly)
        end
    end
end

local function ProcessEllesmereOwner(button)
    if not button then return 0 end
    ProtectButtonText(button)
    local targets={}
    -- Once an owner is selected, include all of its assistant-arrow layers so
    -- hidden/original/custom modes remain stable even after HCAA sets alpha to 0.
    CollectEllesmereTargets(button,0,setmetatable({}, {__mode="k"}),targets,false)
    if #targets==0 then
        HideCustomOverlay(button)
        ellesmereOwners[button]=nil
        return 0
    end
    ellesmereOwners[button]=true
    local p=Profile()
    if p.mode=="custom" then
        for _,tex in ipairs(targets) do
            Remember(tex); managed[tex]=true; arrowTextures[tex]=true
            Restore(tex); tex:Show(); tex:SetAlpha(0); HideGlowFor(tex)
        end
        EnsureCustomOverlay(button,targets[1],false)
    else
        -- Hidden and Original must never leave the custom decoration visible.
        HideCustomOverlay(button)
        for _,tex in ipairs(targets) do ApplyTextureStyle(tex,false) end
    end
    return #targets
end

local function GetButtonActionSlot(button)
    if not button then return nil end
    local action=rawget(button,"action")
    if not action and button.GetAttribute then
        local ok,v=pcall(button.GetAttribute,button,"action")
        if ok then action=v end
    end
    if not action then action=rawget(button,"_state_action") end
    if not action and button.GetPagedID then
        local ok,v=pcall(button.GetPagedID,button)
        if ok then action=v end
    end
    return tonumber(action)
end

local function ButtonHasAssistantAction(button)
    local slot=GetButtonActionSlot(button)
    if not slot then return false end
    if C_ActionBar and C_ActionBar.IsAssistedCombatAction then
        local ok,isAssistant=pcall(C_ActionBar.IsAssistedCombatAction,slot)
        if ok and isAssistant then return true end
    end
    local actionType
    if C_ActionBar and C_ActionBar.GetActionInfo then
        local ok,info=pcall(C_ActionBar.GetActionInfo,slot)
        if ok and type(info)=="table" then actionType=info.type or info.actionType end
    end
    if not actionType and GetActionInfo then
        local ok,t=pcall(GetActionInfo,slot)
        if ok then actionType=t end
    end
    actionType=tostring(actionType or ""):lower()
    return actionType:find("assist",1,true)~=nil or actionType:find("rotation",1,true)~=nil
end

local function FindVisibleEllesmereOwners()
    -- Prefer the actual action assigned to each EllesmereUI button. This keeps
    -- detection working when the assistant action is dragged between bars, even
    -- before the decorative helper texture becomes visible on the destination.
    local owners={}
    for i=1,300 do
        local button=_G["EABButton"..i]
        if button and button.IsShown and button:IsShown() then
            if ButtonHasAssistantAction(button) then
                owners[button]=true
            else
                local visible={}
                CollectEllesmereTargets(button,0,setmetatable({}, {__mode="k"}),visible,true)
                if #visible>0 then owners[button]=true end
            end
        end
    end
    return owners
end
local function OwnerStillUsable(button)
    if not button or not button.IsShown then return false end
    local ok,shown=pcall(button.IsShown,button)
    if not ok or not shown then return false end
    if ButtonHasAssistantAction(button) then return true end
    local targets={}
    CollectEllesmereTargets(button,0,setmetatable({}, {__mode="k"}),targets,false)
    return #targets>0
end
local function ScanEllesmere()
    -- Detect all newly visible copies before HCAA changes their alpha. Cached
    -- owners remain active after their Blizzard textures are hidden, so every
    -- duplicate assistant button continues to receive the same style.
    local visibleOwners=FindVisibleEllesmereOwners()
    for button in pairs(visibleOwners) do activeEllesmereOwners[button]=true end

    local n=0
    for button in pairs(activeEllesmereOwners) do
        if not OwnerStillUsable(button) then
            HideCustomOverlay(button)
            ellesmereOwners[button]=nil
            activeEllesmereOwners[button]=nil
        else
            local ok,count=pcall(ProcessEllesmereOwner,button)
            if ok then
                n=n+(count or 0)
            elseif RecordScanError then
                RecordScanError("EllesmereUI owner",count)
            end
        end
    end
    return n
end
local function HideElvUIAssistGlow(button)
    if not button then return end
    for _,key in ipairs({"_ButtonGlow","_PixelGlow","_AutoCastGlow","_ProcGlow"}) do
        local glow=rawget(button,key)
        if glow and glow.Hide then pcall(glow.Hide,glow) end
    end
    -- Some LibCustomGlow styles append a key suffix. Hide only glow-owned fields.
    if type(button)=="table" then
        for key,value in pairs(button) do
            if type(key)=="string" and key:find("Glow",1,true) and value and value.Hide and key:sub(1,1)=="_" then
                pcall(value.Hide,value)
            end
        end
    end
end

local function ProcessElvUIButton(button)
    if not button or not ButtonHasAssistantAction(button) then
        if button then HideCustomOverlay(button); elvuiOwners[button]=nil end
        return 0
    end
    ProtectButtonText(button)
    elvuiOwners[button]=true
    local p=Profile()
    local anchor=button.icon or button.Icon or button
    if p.mode=="custom" then
        HideElvUIAssistGlow(button)
        EnsureCustomOverlay(button,anchor,false)
    elseif p.mode=="hidden" then
        HideCustomOverlay(button)
        HideElvUIAssistGlow(button)
    else
        HideCustomOverlay(button)
    end
    return 1
end

local function ForEachElvUIButton(fn)
    local seen=setmetatable({}, {__mode="k"})
    for bar=1,15 do
        for i=1,12 do
            local button=_G["ElvUI_Bar"..bar.."Button"..i]
            if button and not seen[button] then seen[button]=true; fn(button) end
        end
    end
    -- Also catch buttons registered by LibActionButton even if a custom ElvUI layout
    -- uses a nonstandard bar index or button name.
    local E=_G.ElvUI and _G.ElvUI[1]
    local LAB=E and E.Libs and E.Libs.LAB
    if LAB and LAB.activeButtons then
        for button in pairs(LAB.activeButtons) do
            if button and not seen[button] then seen[button]=true; fn(button) end
        end
    end
end

local function HookElvUIButton(button)
    if not button or hookedElvUIButtons[button] or not button.HookScript then return end
    hookedElvUIButtons[button]=true
    button:HookScript("OnShow",function() ScheduleScan(0.02) end)
    button:HookScript("OnAttributeChanged",function(_,name)
        if name=="action" or name=="type" or name=="state-action" then ScheduleScan(0.02) end
    end)
end

local function InstallElvUIHooks()
    if not Loaded("ElvUI") then return end
    ForEachElvUIButton(HookElvUIButton)
    if elvuiAssistHooked then return end
    local E=_G.ElvUI and _G.ElvUI[1]
    local AB=E and E.GetModule and E:GetModule("ActionBars",true)
    if AB and type(AB.AssistedUpdate)=="function" and hooksecurefunc then
        elvuiAssistHooked=true
        hooksecurefunc(AB,"AssistedUpdate",function()
            C_Timer.After(0,function() if HCAA_DB then ScanAll() end end)
        end)
    end
end

local function ScanElvUI()
    if not Loaded("ElvUI") then return 0 end
    InstallElvUIHooks()
    local n=0
    ForEachElvUIButton(function(button)
        local ok,count=pcall(ProcessElvUIButton,button)
        if ok then n=n+(count or 0) elseif RecordScanError then RecordScanError("ElvUI button",count) end
    end)
    -- Remove stale overlays from buttons that no longer carry the assistant action.
    for button in pairs(elvuiOwners) do
        if not ButtonHasAssistantAction(button) then
            HideCustomOverlay(button)
            elvuiOwners[button]=nil
        end
    end
    return n
end

RecordScanError=function(context,err)
    local key=context..":"..tostring(err); runtimeStatus.lastError=tostring(err); runtimeStatus.scanHadError=true
    if runtimeStatus.lastErrorKey~=key then runtimeStatus.lastErrorKey=key; Print(context.." scan failed safely: "..tostring(err)) end
end
local function SafeScan(context,fn)
    local ok,count=pcall(fn)
    if not ok then RecordScanError(context,count); return 0,false end
    return tonumber(count) or 0,true
end
local function StopPulseTicker()
    if pulseTicker then pulseTicker:Cancel(); pulseTicker=nil end
end

ApplyCached=function()
    if not HCAA_DB then return end
    local p=Profile()
    if not p.enabled then
        StopPulseTicker()
        for o in pairs(managed) do Restore(o); local g=glowOverlays[o]; if g then g:Hide() end end
        for owner,overlay in pairs(customOverlays) do if overlay then overlay:Hide(); HideGlowFor(overlay) end end
        return
    end
    if p.mode~="custom" then
        -- Always remove any custom frame left from a previous Custom mode.
        -- EllesmereUI can keep the owner button alive while the underlying
        -- assistant textures change, so relying only on a fresh scan leaves
        -- the old decorative frame visible in Hidden/Original mode.
        for owner,overlay in pairs(customOverlays) do
            if overlay then
                overlay:Hide()
                HideGlowFor(overlay)
            end
        end
        for tex in pairs(arrowTextures) do
            if tex and tex.GetObjectType then
                local ok=pcall(ApplyTextureStyle,tex,false)
                if not ok then arrowTextures[tex]=nil; managed[tex]=nil end
            else
                arrowTextures[tex]=nil; managed[tex]=nil
            end
        end
    else
        for tex in pairs(arrowTextures) do
            if tex and tex.SetAlpha then tex:Show(); tex:SetAlpha(0); HideGlowFor(tex) end
        end
        for owner,overlay in pairs(customOverlays) do
            if owner and overlay and overlay.GetParent then
                local anchor=overlay._hcaaAnchor
                local scale=Clamp(tonumber(p.scale) or 1,.5,2)
                local bw=overlay._hcaaBaseW or 64
                local bh=overlay._hcaaBaseH or 64
                if anchor then
                    overlay:ClearAllPoints()
                    overlay:SetPoint("CENTER",anchor,"CENTER",p.offsetX or 0,p.offsetY or 0)
                end
                overlay:SetSize(bw*scale,bh*scale)
                local useColor=p.colorEnabled~=false
                local c=useColor and (p.color or {1,1,1,1}) or {1,1,1,1}
                overlay:SetTexture(ShapePath(p.shape))
                if overlay.SetDesaturated then overlay:SetDesaturated(useColor) end
                overlay:SetVertexColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1)
                if overlay.SetRotation then overlay:SetRotation(math.rad(tonumber(p.rotation) or 0)) end
                overlay:SetAlpha(EffectiveAlpha())
                overlay:SetShown(EffectiveAlpha()>0)
                UpdateGlow(overlay,false)
            end
        end
    end
    for o in pairs(managed) do
        if o and o.GetObjectType and o:GetObjectType()=="Frame" then pcall(ApplyFrame,o) end
    end
    if p.pulse and p.mode=="custom" then
        if not pulseTicker then StartPulseTicker() end
    else
        StopPulseTicker()
    end
end

ScheduleScan=function(delay)
    if scanPending then return end
    scanPending=true
    C_Timer.After(delay or 0.05,function()
        scanPending=false
        if HCAA_DB then ScanAll() end
    end)
end

ScanAll=function()
    if not HCAA_DB then return 0 end
    runtimeStatus.scanHadError=false
    local p=Profile(); if not p.enabled then ApplyCached(); runtimeStatus.count=0; return 0 end
    local blizzard,blizzardOK=SafeScan("Blizzard UI",ScanBlizzard)
    local ellesmere,ellesmereOK=SafeScan("EllesmereUI",ScanEllesmere)
    local elvui,elvuiOK=SafeScan("ElvUI",ScanElvUI)
    runtimeStatus.blizzard=blizzard; runtimeStatus.ellesmere=ellesmere; runtimeStatus.elvui=elvui; runtimeStatus.count=blizzard+ellesmere+elvui
    if blizzardOK and ellesmereOK and elvuiOK and not runtimeStatus.scanHadError then runtimeStatus.lastError=nil; runtimeStatus.lastErrorKey=nil end
    local n=runtimeStatus.count
    local a=EffectiveAlpha(); if a<=0 then
        local s=HCAA_DB.statistics; if not s.lastStart then s.lastStart=time(); s.hiddenCount=(s.hiddenCount or 0)+1 end
    else
        local s=HCAA_DB.statistics; if s.lastStart then s.hiddenSeconds=(s.hiddenSeconds or 0)+(time()-s.lastStart); s.lastStart=nil end
    end
    return n
end
local function SetEnabled(v) Profile().enabled=not not v; ApplyCached(); if RefreshConfig then RefreshConfig() end; Print(v and "Enabled." or "Disabled.") end
local function SetOpacity(v) Profile().opacity=Clamp(v,0,1); ApplyCached(); if RefreshConfig then RefreshConfig() end end
local function SetMode(m)
    if m=="original" and IsEllesmereUI() then
        Print("Blizzard Original mode is available only with Blizzard UI. Use Hidden or Custom with EllesmereUI.")
        m="custom"
    end
    if m=="hidden" or m=="original" or m=="custom" then
        Profile().mode=m
        ApplyCached()
        -- Re-detect EllesmereUI targets after a mode switch. Its action-button
        -- helper can recreate or swap arrow regions without firing OnShow on
        -- the previously cached texture.
        ScheduleScan(0.02)
        if RefreshConfig then RefreshConfig() end
    end
end

local function ExportString()
    local p=Profile(); local c=p.color or {1,1,1,1}; local g=p.glowColor or {1,.78,.05,1}
    return table.concat({"HCAA1",p.enabled and 1 or 0,p.opacity,p.mode,p.shape,c[1],c[2],c[3],c[4],p.scale,p.rotation,p.glow and 1 or 0,p.pulse and 1 or 0,p.fade and 1 or 0,p.fadeDuration,p.autoCombat,g[1],g[2],g[3],g[4],p.glowIntensity or .65,p.flashOnProc and 1 or 0,p.pulseSpeed or 1.5,p.offsetX or 0,p.offsetY or 0,p.colorEnabled and 1 or 0},"|")
end
local function ImportString(s)
    local t={} for x in tostring(s):gmatch("([^|]+)") do t[#t+1]=x end
    if t[1]~="HCAA1" then return false,"Invalid HCAA profile string." end
    local p=Profile(); p.enabled=t[2]=="1"; p.opacity=Clamp(t[3],0,1); p.mode=t[4] or "hidden"; p.shape=NormalizeShape(t[5])
    p.color={Clamp(t[6],0,1),Clamp(t[7],0,1),Clamp(t[8],0,1),Clamp(t[9],0,1)}; p.scale=Clamp(t[10],.5,2); p.rotation=tonumber(t[11]) or 0
    p.glow=t[12]=="1"; p.pulse=t[13]=="1"; p.fade=t[14]=="1"; p.fadeDuration=Clamp(t[15],.05,2); p.autoCombat=t[16] or "none"
    if t[1]=="HCAA1" then
        p.glowColor={Clamp(t[17],0,1),Clamp(t[18],0,1),Clamp(t[19],0,1),Clamp(t[20],0,1)}
        p.glowIntensity=Clamp(t[21],0,1); p.flashOnProc=t[22]=="1"; p.pulseSpeed=Clamp(t[23],.5,3)
        p.offsetX=Clamp(t[24] or 0,-80,80); p.offsetY=Clamp(t[25] or 0,-80,80)
        p.colorEnabled=t[26]~="0"
    end
    ApplyCached(); if RefreshConfig then RefreshConfig() end; return true
end

local function PopupEdit(title,text,onAccept)
    StaticPopupDialogs.HCAA_EDIT={text=title,button1=ACCEPT,button2=CANCEL,hasEditBox=true,editBoxWidth=420,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnShow=function(self) self.EditBox:SetText(text or ""); self.EditBox:HighlightText(); self.EditBox:SetFocus() end,
        OnAccept=function(self) if onAccept then onAccept(self.EditBox:GetText()) end end,
        EditBoxOnEnterPressed=function(self) local p=self:GetParent(); if onAccept then onAccept(self:GetText()) end p:Hide() end}
    StaticPopup_Show("HCAA_EDIT")
end

local function CreateLabel(parent,text,x,y,font) local f=parent:CreateFontString(nil,"ARTWORK",font or "GameFontNormal"); f:SetPoint("TOPLEFT",x,y); f:SetText(text); return f end
local function CreateCheck(parent,text,x,y,get,set)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate"); b:SetPoint("TOPLEFT",x,y); b.Text:SetText(text); b:SetScript("OnShow",function(self) self:SetChecked(get()) end); b:SetScript("OnClick",function(self) set(self:GetChecked()) end); return b
end
local function CreateSlider(parent,name,label,x,y,min,max,step,get,set)
    CreateLabel(parent,label,x,y); local s=CreateFrame("Slider",name,parent,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",x+4,y-28); s:SetWidth(270); s:SetMinMaxValues(min,max); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    _G[name.."Low"]:SetText(tostring(min)); _G[name.."High"]:SetText(tostring(max)); local v=parent:CreateFontString(nil,"ARTWORK","GameFontHighlight"); v:SetPoint("LEFT",s,"RIGHT",15,0)
    s:SetScript("OnShow",function(self) self._syncing=true; self:SetValue(get()); v:SetText(string.format("%.2f",get())); self._syncing=false end)
    s:SetScript("OnValueChanged",function(self,val)
        val=math.floor(val/step+.5)*step; v:SetText(string.format("%.2f",val))
        if self._syncing then return end
        set(val)
    end)
    return s
end

local colorFrame
function OpenHCAAColorPicker()
    local p=Profile(); local old={unpack(p.color or {1,1,1,1})}
    if not colorFrame then
        local f=CreateFrame("Frame","HCAAColorFrame",UIParent,"BasicFrameTemplateWithInset")
        f:SetSize(390,300); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
        f.TitleText:SetText("HCAA Custom Color")
        local preview=f:CreateTexture(nil,"ARTWORK"); preview:SetSize(90,90); preview:SetPoint("TOPLEFT",28,-55); preview:SetTexture("Interface\\AddOns\\HCAA\\Shapes\\circle")
        f.preview=preview
        local vals={}
        local function mk(label,y,key)
            local fs=f:CreateFontString(nil,"ARTWORK","GameFontNormal"); fs:SetPoint("TOPLEFT",145,y); fs:SetText(label)
            local s=CreateFrame("Slider",nil,f,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",145,y-22); s:SetWidth(205); s:SetMinMaxValues(0,100); s:SetValueStep(1); s:SetObeyStepOnDrag(true)
            local v=f:CreateFontString(nil,"ARTWORK","GameFontHighlight"); v:SetPoint("LEFT",s,"RIGHT",8,0)
            s:SetScript("OnValueChanged",function(_,x) vals[key]=x/100; v:SetText(math.floor(x+0.5).."%"); if f.preview then f.preview:SetVertexColor(vals.r or 1,vals.g or 1,vals.b or 1,vals.a or 1) end end)
            f[key]=s
        end
        mk("Red",-52,"r"); mk("Green",-98,"g"); mk("Blue",-144,"b"); mk("Alpha",-190,"a")
        local ok=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); ok:SetSize(120,26); ok:SetPoint("BOTTOMRIGHT",-22,18); ok:SetText("Apply & Close")
        ok:SetScript("OnClick",function() local pp=Profile(); pp.color={vals.r or 1,vals.g or 1,vals.b or 1,vals.a or 1}; ApplyCached(); f:Hide() end)
        local cancel=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); cancel:SetSize(100,26); cancel:SetPoint("RIGHT",ok,"LEFT",-10,0); cancel:SetText("Cancel")
        cancel:SetScript("OnClick",function() local pp=Profile(); pp.color={unpack(f.oldColor or {1,1,1,1})}; ApplyCached(); f:Hide() end)
        f.CloseButton:SetScript("OnClick",function() local pp=Profile(); pp.color={unpack(f.oldColor or {1,1,1,1})}; ApplyCached(); f:Hide() end)
        f.vals=vals; colorFrame=f
    end
    colorFrame.oldColor=old
    local cc=p.color or {1,1,1,1}
    colorFrame.vals.r,colorFrame.vals.g,colorFrame.vals.b,colorFrame.vals.a=cc[1],cc[2],cc[3],cc[4]
    colorFrame.r:SetValue((cc[1] or 1)*100); colorFrame.g:SetValue((cc[2] or 1)*100); colorFrame.b:SetValue((cc[3] or 1)*100); colorFrame.a:SetValue((cc[4] or 1)*100)
    colorFrame.preview:SetTexture(ShapePath(p.shape)); if colorFrame.preview.SetDesaturated then colorFrame.preview:SetDesaturated(true) end; colorFrame.preview:SetVertexColor(cc[1] or 1,cc[2] or 1,cc[3] or 1,cc[4] or 1)
    colorFrame:Show(); colorFrame:Raise()
end

RefreshConfig=function() if configFrame and configFrame:IsShown() then configFrame:Hide(); configFrame:Show() end end
local function CreateConfig()
    local f=CreateFrame("Frame","HCAAConfigFrame",UIParent,"BasicFrameTemplateWithInset"); f:SetSize(720,650); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide()
    f.TitleText:SetText("HCAA v"..VERSION.." - Hide And Customize Assistant Arrow")
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",12,-34); scroll:SetPoint("BOTTOMRIGHT",-30,12)
    local c=CreateFrame("Frame",nil,scroll); c:SetSize(650,1180); scroll:SetScrollChild(c)
    CreateLabel(c,"Profile",16,-10,"GameFontNormalLarge")
    local profile=CreateFrame("Frame",nil,c,"UIDropDownMenuTemplate"); profile:SetPoint("TOPLEFT",0,-35); UIDropDownMenu_SetWidth(profile,180)
    UIDropDownMenu_Initialize(profile,function(self,level) for _,m in ipairs({{"Account-wide","account"},{"Per Character","character"},{"Per Specialization","spec"}}) do local i=UIDropDownMenu_CreateInfo(); i.text=m[1]; i.checked=HCAA_DB.profileMode==m[2]; i.func=function() HCAA_DB.profileMode=m[2]; UIDropDownMenu_SetText(profile,m[1]); ApplyCached(); RefreshConfig() end; UIDropDownMenu_AddButton(i,level) end end)
    profile:SetScript("OnShow",function() local map={account="Account-wide",character="Per Character",spec="Per Specialization"}; UIDropDownMenu_SetText(profile,map[HCAA_DB.profileMode] or "Account-wide") end)
    CreateCheck(c,"Enable HCAA",16,-85,function() return Profile().enabled end,function(v) SetEnabled(v) end)
    CreateCheck(c,"Show minimap button",250,-85,function() return not HCAA_DB.minimap.hide end,function(v) HCAA_DB.minimap.hide=not v; if minimapButton then if v then minimapButton:Show() else minimapButton:Hide() end end end)
    CreateLabel(c,"Arrow Mode",16,-130,"GameFontNormalLarge")
    local mode=CreateFrame("Frame",nil,c,"UIDropDownMenuTemplate"); mode:SetPoint("TOPLEFT",0,-155); UIDropDownMenu_SetWidth(mode,180)
    UIDropDownMenu_Initialize(mode,function(self,level) local modes=IsEllesmereUI() and {{"Hidden","hidden"},{"Custom Shape","custom"}} or {{"Hidden","hidden"},{"Blizzard Original","original"},{"Custom Shape","custom"}}; for _,m in ipairs(modes) do local i=UIDropDownMenu_CreateInfo(); i.text=m[1]; i.checked=Profile().mode==m[2]; i.func=function() SetMode(m[2]); UIDropDownMenu_SetText(mode,m[1]) end; UIDropDownMenu_AddButton(i,level) end end)
    mode:SetScript("OnShow",function() local map={hidden="Hidden",original="Blizzard Original",custom="Custom Shape"}; UIDropDownMenu_SetText(mode,map[Profile().mode]) end)
    CreateSlider(c,"HCAAOpacity","Opacity (%)",16,-210,0,100,1,function() return (Profile().opacity or 0)*100 end,function(v) Profile().opacity=Clamp(v/100,0,1); ScheduleVisualApply() end)
    CreateSlider(c,"HCAAScale","Scale",350,-210,.5,2,.05,function() return Profile().scale or 1 end,function(v) Profile().scale=v; ScheduleVisualApply() end)
    CreateSlider(c,"HCAARotation","Rotation (degrees)",16,-295,0,360,5,function() return Profile().rotation or 0 end,function(v) Profile().rotation=v; ScheduleVisualApply() end)
    CreateSlider(c,"HCAAFadeDuration","Fade duration",350,-295,.05,1.5,.05,function() return Profile().fadeDuration or .2 end,function(v) Profile().fadeDuration=v end)
    CreateCheck(c,"Smooth fade",16,-380,function() return Profile().fade end,function(v) Profile().fade=v; ApplyCached() end)
    CreateCheck(c,"Glow / additive blend",180,-380,function() return Profile().glow end,function(v) Profile().glow=v; ApplyCached() end)
    CreateCheck(c,"Pulse animation",410,-380,function() return Profile().pulse end,function(v) Profile().pulse=v end)
    CreateLabel(c,"Custom Shape (20 included)",16,-425,"GameFontNormalLarge")
    shapeDropdown=CreateFrame("Frame",nil,c,"UIDropDownMenuTemplate"); shapeDropdown:SetPoint("TOPLEFT",0,-450); UIDropDownMenu_SetWidth(shapeDropdown,210)
    UIDropDownMenu_Initialize(shapeDropdown,function(self,level) for _,s in ipairs(SHAPES) do local i=UIDropDownMenu_CreateInfo(); i.text=SHAPE_LABELS[s]; i.checked=Profile().shape==s; i.func=function() Profile().shape=s; Profile().mode="custom"; UIDropDownMenu_SetText(shapeDropdown,SHAPE_LABELS[s]); ApplyCached() end; UIDropDownMenu_AddButton(i,level) end end)
    shapeDropdown:SetScript("OnShow",function() UIDropDownMenu_SetText(shapeDropdown,SHAPE_LABELS[Profile().shape] or "Original") end)
    local color=CreateFrame("Button",nil,c,"UIPanelButtonTemplate"); color:SetSize(150,24); color:SetPoint("TOPLEFT",300,-458); color:SetText("Customize Color")
    color:SetScript("OnClick",function() OpenHCAAColorPicker() end)
    CreateLabel(c,"Automatic Rules",16,-510,"GameFontNormalLarge")
    local combat=CreateFrame("Frame",nil,c,"UIDropDownMenuTemplate"); combat:SetPoint("TOPLEFT",0,-535); UIDropDownMenu_SetWidth(combat,210)
    local combatOpts={{"No combat rule","none"},{"Hide while in combat","hide_in_combat"},{"Show only in combat","show_in_combat"}}
    UIDropDownMenu_Initialize(combat,function(self,level) for _,m in ipairs(combatOpts) do local i=UIDropDownMenu_CreateInfo(); i.text=m[1]; i.checked=Profile().autoCombat==m[2]; i.func=function() Profile().autoCombat=m[2]; UIDropDownMenu_SetText(combat,m[1]); ApplyCached() end; UIDropDownMenu_AddButton(i,level) end end)
    combat:SetScript("OnShow",function() for _,m in ipairs(combatOpts) do if m[2]==Profile().autoCombat then UIDropDownMenu_SetText(combat,m[1]) end end end)
    local zx,zy=16,-590
    for idx,z in ipairs({{"Solo / Open World","solo"},{"Dungeon","dungeon"},{"Raid","raid"},{"Arena","arena"},{"Battleground","battleground"}}) do CreateCheck(c,z[1],zx+((idx-1)%3)*200,zy-math.floor((idx-1)/3)*35,function() return Profile().zones[z[2]]~=false end,function(v) Profile().zones[z[2]]=v; ApplyCached() end) end
    CreateLabel(c,"Utilities",16,-680,"GameFontNormalLarge")
    local exp=CreateFrame("Button",nil,c,"UIPanelButtonTemplate"); exp:SetSize(140,24); exp:SetPoint("TOPLEFT",16,-715); exp:SetText("Export Settings"); exp:SetScript("OnClick",function() PopupEdit("Copy your HCAA profile:",ExportString()) end)
    local imp=CreateFrame("Button",nil,c,"UIPanelButtonTemplate"); imp:SetSize(140,24); imp:SetPoint("LEFT",exp,"RIGHT",12,0); imp:SetText("Import Settings"); imp:SetScript("OnClick",function() PopupEdit("Paste an HCAA profile string:","",function(s) local ok,err=ImportString(s); Print(ok and "Profile imported." or err); RefreshConfig() end) end)
    local reset=CreateFrame("Button",nil,c,"UIPanelButtonTemplate"); reset:SetSize(140,24); reset:SetPoint("LEFT",imp,"RIGHT",12,0); reset:SetText("Reset Profile"); reset:SetScript("OnClick",function() local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); RefreshConfig(); Print("Current profile reset.") end)
    local compat=CreateLabel(c,"Compatibility: "..DetectedUI(),16,-770,"GameFontHighlight")
    local stats=CreateLabel(c,"",16,-800,"GameFontHighlight"); stats:SetScript("OnShow",function(self) local s=HCAA_DB.statistics; self:SetText(string.format("Statistics - hidden events: %d | hidden time: %dm %ds",s.hiddenCount or 0,math.floor((s.hiddenSeconds or 0)/60),(s.hiddenSeconds or 0)%60)) end)
    CreateLabel(c,"Keybind: Set 'Toggle HCAA' in Game Menu > Options > Keybindings > AddOns.",16,-835,"GameFontHighlightSmall")
    CreateLabel(c,"Slash commands: /hcaa on | off | toggle | opacity 0-100 | mode hidden/original/custom | shape name | export | import | reset",16,-865,"GameFontHighlightSmall")
    configFrame=f
end
local function OpenConfig() if not configFrame then CreateConfig() end if configFrame:IsShown() then configFrame:Hide() else configFrame:Show() end end

-- Screenshot-inspired v1.4.1 official interface. The legacy builder above remains
-- as a lightweight fallback reference; OpenConfig is reassigned below.
local GOLD_R,GOLD_G,GOLD_B=1,.78,.08
local hSliderSerial=0
local hBuildingConfig
local function HRegisterRefresh(fn) if hBuildingConfig then hBuildingConfig.refreshers[#hBuildingConfig.refreshers+1]=fn end end
local function HLabel(parent,text,x,y,font,r,g,b)
    local fs=parent:CreateFontString(nil,"ARTWORK",font or "GameFontNormal"); fs:SetPoint("TOPLEFT",x,y); fs:SetText(text)
    if r then fs:SetTextColor(r,g,b) end
    return fs
end
local function HPanel(parent,title)
    local p=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    p:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    p:SetBackdropColor(.015,.03,.03,.94); p:SetBackdropBorderColor(.28,.27,.20,1)
    if title then HLabel(p,title,12,-9,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B) end
    return p
end
local function HButton(parent,text,w,h)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetSize(w or 120,h or 25); b:SetText(text); return b
end
local function HCheck(parent,text,x,y,get,set,enabledWhen)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate"); b:SetPoint("TOPLEFT",x,y); b:SetSize(26,26)
    local label
    if b.Text then b.Text:SetText(text); label=b.Text else label=HLabel(b,text,27,-6,"GameFontHighlight") end
    local function refresh()
        b:SetChecked(not not get())
        local enabled=not enabledWhen or enabledWhen()
        if enabled then
            b:Enable(); b:SetAlpha(1); if label and label.SetTextColor then label:SetTextColor(1,1,1) end
        else
            b:Disable(); b:SetAlpha(.45); if label and label.SetTextColor then label:SetTextColor(.5,.5,.5) end
        end
    end; HRegisterRefresh(refresh)
    b:SetScript("OnClick",function(self)
        if enabledWhen and not enabledWhen() then self:SetChecked(not not get()); return end
        set(not not self:GetChecked()); ApplyCached(); RefreshConfig()
    end)
    return b
end
local function HSlider(parent,label,x,y,w,min,max,step,get,set,formatter,enabledWhen)
    hSliderSerial=hSliderSerial+1; local name="HCAAStyledSlider"..hSliderSerial
    local labelText=HLabel(parent,label,x,y,"GameFontHighlight")
    local value=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); value:SetPoint("TOPRIGHT",parent,"TOPLEFT",x+w,y)
    local s=CreateFrame("Slider",name,parent,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",x+3,y-18); s:SetWidth(w-6); s:SetMinMaxValues(min,max); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    if _G[name.."Low"] then _G[name.."Low"]:SetText(tostring(min)) end; if _G[name.."High"] then _G[name.."High"]:SetText(tostring(max)) end; if _G[name.."Text"] then _G[name.."Text"]:SetText("") end
    local function fmt(v) return formatter and formatter(v) or string.format("%.2f",v) end
    local function refresh()
        local v=get(); s._refresh=true; s:SetValue(v); s._refresh=false; value:SetText(fmt(v))
        local enabled=not enabledWhen or enabledWhen()
        if enabled then
            s:Enable(); s:SetAlpha(1); labelText:SetTextColor(1,1,1); value:SetTextColor(1,1,1)
        else
            s:Disable(); s:SetAlpha(.45); labelText:SetTextColor(.5,.5,.5); value:SetTextColor(.5,.5,.5)
        end
    end; HRegisterRefresh(refresh)
    s:SetScript("OnValueChanged",function(self,v)
        v=math.floor(v/step+.5)*step
        value:SetText(fmt(v))
        if not self._refresh and (not enabledWhen or enabledWhen()) then
            set(v)
            ScheduleVisualApply()
        end
    end)
    return s
end
local function HDropdown(parent,x,y,w,options,get,set)
    local d=CreateFrame("Frame",nil,parent,"UIDropDownMenuTemplate"); d:SetPoint("TOPLEFT",x-15,y); UIDropDownMenu_SetWidth(d,w)
    UIDropDownMenu_Initialize(d,function(_,level)
        for _,opt in ipairs(options) do local label,value=opt[1],opt[2]; local info=UIDropDownMenu_CreateInfo(); info.text=label; info.checked=get()==value; info.func=function() set(value); UIDropDownMenu_SetText(d,label); ApplyCached(); RefreshConfig() end; UIDropDownMenu_AddButton(info,level) end
    end)
    HRegisterRefresh(function() local current=get(); local label=current; for _,opt in ipairs(options) do if opt[2]==current then label=opt[1]; break end end; UIDropDownMenu_SetText(d,label or "") end)
    return d
end
local function HSwatch(parent,x,y,size,get)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize(size,size); b:SetPoint("TOPLEFT",x,y); b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
    HRegisterRefresh(function() local c=get(); b:SetBackdropColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1); b:SetBackdropBorderColor(.8,.7,.25,1) end)
    return b
end

-- Dedicated RGBA editor with a native color-wheel launcher and preset swatches.
function OpenHCAAColorPicker(kind)
    kind=kind=="glow" and "glow" or "arrow"; local p=Profile()
    if kind=="glow" and p.mode~="custom" then return end
    local source=kind=="glow" and (p.glowColor or {1,.78,.05,1}) or (p.color or {1,1,1,1})
    if not colorFrame or not colorFrame.hModern then
        local f=CreateFrame("Frame","HCAAColorFrameModern",UIParent,"BasicFrameTemplateWithInset"); f.hModern=true
        f:SetSize(470,410); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
        local pp=HPanel(f,"Preview"); pp:SetPoint("TOPLEFT",16,-42); pp:SetSize(145,205)
        f.preview=pp:CreateTexture(nil,"ARTWORK"); f.preview:SetSize(112,112); f.preview:SetPoint("TOP",0,-45)
        f.vals={r=1,g=1,b=1,a=1}; f.sliders={}
        function f:UpdateColorControls()
            local v=self.vals
            local profile=Profile()
            if self.kind=="arrow" and profile.mode=="original" and self.preview.SetAtlas then
                self.preview:SetAtlas("UI-HUD-RotationHelper-Active-2x",true)
                if self.preview.SetDesaturated then self.preview:SetDesaturated(false) end
            else
                self.preview:SetTexture(ShapePath(profile.shape))
                if self.preview.SetDesaturated then self.preview:SetDesaturated(true) end
            end
            self.preview:SetVertexColor(v.r,v.g,v.b,v.a)
            for key,s in pairs(self.sliders) do s._refresh=true; s:SetValue((v[key] or 1)*100); s._refresh=false; s.value:SetText(string.format("%.2f",v[key] or 1)) end
        end
        function f:PreviewLive()
            local v=self.vals; local target=self.targetProfile
            if not target then return end
            local color={v.r,v.g,v.b,v.a}
            if self.kind=="glow" then target.glowColor=color else target.color=color end
            self.preview:SetVertexColor(v.r,v.g,v.b,v.a); ApplyCached(); RefreshConfig()
        end
        local rows={{"R",.95,.2,.2,"r"},{"G",.2,1,.2,"g"},{"B",.3,.6,1,"b"},{"A",1,1,1,"a"}}
        for index,row in ipairs(rows) do
            local key=row[5]; local y=-50-(index-1)*47; HLabel(f,row[1],180,y,"GameFontNormal",row[2],row[3],row[4]); hSliderSerial=hSliderSerial+1; local name="HCAAColorSlider"..hSliderSerial
            local s=CreateFrame("Slider",name,f,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",202,y-17); s:SetWidth(205); s:SetMinMaxValues(0,100); s:SetValueStep(1); s:SetObeyStepOnDrag(true)
            if _G[name.."Low"] then _G[name.."Low"]:SetText("0") end; if _G[name.."High"] then _G[name.."High"]:SetText("1") end; if _G[name.."Text"] then _G[name.."Text"]:SetText("") end
            local out=f:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); out:SetPoint("LEFT",s,"RIGHT",7,0); s.value=out; f.sliders[key]=s
            s:SetScript("OnValueChanged",function(self,v) if not self._refresh then f.vals[key]=v/100; f:PreviewLive() end; out:SetText(string.format("%.2f",v/100)) end)
        end
        local wheel=HButton(f,"Open Color Wheel",145,26); wheel:SetPoint("TOPLEFT",16,-255)
        wheel:SetScript("OnClick",function()
            local v=f.vals; local before={v.r,v.g,v.b}; local function changed() v.r,v.g,v.b=ColorPickerFrame:GetColorRGB(); f:UpdateColorControls(); f:PreviewLive() end
            if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow({r=v.r,g=v.g,b=v.b,hasOpacity=false,swatchFunc=changed,cancelFunc=function() v.r,v.g,v.b=before[1],before[2],before[3]; f:UpdateColorControls(); f:PreviewLive() end})
            else ColorPickerFrame:SetColorRGB(v.r,v.g,v.b); ColorPickerFrame.func=changed; ColorPickerFrame.cancelFunc=function() v.r,v.g,v.b=before[1],before[2],before[3]; f:UpdateColorControls(); f:PreviewLive() end; ColorPickerFrame:Show() end
        end)
        local presets={{1,.05,.02,1},{1,.45,.02,1},{1,.8,.02,1},{.1,1,.1,1},{.02,.8,.7,1},{.1,.65,1,1},{.45,.2,1,1},{1,1,1,1}}
        for i,c in ipairs(presets) do local preset=c; local sw=CreateFrame("Button",nil,f,"BackdropTemplate"); sw:SetSize(36,25); sw:SetPoint("TOPLEFT",17+(i-1)*54,-298); sw:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=9}); sw:SetBackdropColor(preset[1],preset[2],preset[3],1); sw:SetScript("OnClick",function() f.vals.r,f.vals.g,f.vals.b,f.vals.a=preset[1],preset[2],preset[3],preset[4]; f:UpdateColorControls(); f:PreviewLive() end) end
        local ok=HButton(f,"Apply & Close",125,26); ok:SetPoint("BOTTOMRIGHT",-18,16); local cancel=HButton(f,"Cancel",100,26); cancel:SetPoint("RIGHT",ok,"LEFT",-10,0)
        local function cancelColor() local target=f.targetProfile; if target and f.oldColor then local c=DeepCopy(f.oldColor); if f.kind=="glow" then target.glowColor=c else target.color=c end; ApplyCached(); RefreshConfig() end; f:Hide() end
        ok:SetScript("OnClick",function() f:PreviewLive(); f.oldColor=nil; RefreshConfig(); f:Hide() end)
        cancel:SetScript("OnClick",cancelColor); f.CloseButton:SetScript("OnClick",cancelColor); colorFrame=f
    end
    colorFrame.kind=kind; colorFrame.targetProfile=p; colorFrame.oldColor=DeepCopy(source); colorFrame.TitleText:SetText(kind=="glow" and "HCAA - Glow Color" or "HCAA - Arrow Color")
    local v=colorFrame.vals; v.r,v.g,v.b,v.a=source[1] or 1,source[2] or 1,source[3] or 1,source[4] or 1; colorFrame:UpdateColorControls(); colorFrame:Show(); colorFrame:Raise()
end

local function HSelectShape(shape)
    local p=Profile()
    if p.mode~="custom" then return end
    p.shape=shape
    ApplyCached()
    RefreshConfig()
end
local function HBuildGeneral(owner,page)
    local mode=HPanel(page,"1. Arrow Mode"); mode:SetPoint("TOPLEFT",0,0); mode:SetSize(198,170)
    local modeOptions=IsEllesmereUI() and {{"Hidden","hidden"},{"Custom","custom"}} or {{"Hidden","hidden"},{"Blizzard Original","original"},{"Custom","custom"}}
    HDropdown(mode,12,-34,150,modeOptions,function() return Profile().mode end,function(v) SetMode(v) end)
    HCheck(mode,"Enable HCAA",12,-82,function() return Profile().enabled end,function(v) Profile().enabled=v end)
    local help=HLabel(mode,"Hide, keep Blizzard's arrow,\nor use your custom design.",14,-120,"GameFontHighlightSmall",.72,.72,.72); help:SetSpacing(3)

    local prev=HPanel(page,"2. Preview"); prev:SetPoint("TOPLEFT",203,0); prev:SetSize(190,170)
    local glow=prev:CreateTexture(nil,"ARTWORK",nil,1); glow:SetBlendMode("ADD"); local arrow=prev:CreateTexture(nil,"ARTWORK",nil,2)
    local left=HButton(prev,"<",28,28); left:SetPoint("LEFT",8,3); left:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().rotation=(Profile().rotation-15)%360; ApplyCached(); RefreshConfig() end)
    local right=HButton(prev,">",28,28); right:SetPoint("RIGHT",-8,3); right:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().rotation=(Profile().rotation+15)%360; ApplyCached(); RefreshConfig() end)
    local info=prev:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); info:SetPoint("BOTTOM",0,28)
    local reset=HButton(prev,"Reset Size / Rotation",145,22); reset:SetPoint("BOTTOM",0,5); reset:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().scale=1; Profile().rotation=0; Profile().offsetX=0; Profile().offsetY=0; ApplyCached(); RefreshConfig() end)
    HRegisterRefresh(function()
        local p=Profile(); local useColor=p.colorEnabled~=false; local c=useColor and (p.color or {1,1,1,1}) or {1,1,1,1}; local gc=p.glowColor or {1,.78,.05,1}; local custom=p.mode=="custom"; local shown=p.mode~="hidden"
        local size=custom and Clamp(72*(p.scale or 1),48,108) or 72
        arrow:ClearAllPoints(); arrow:SetPoint("CENTER",p.offsetX or 0,4+(p.offsetY or 0)); arrow:SetSize(size,size)
        if p.mode=="original" and arrow.SetAtlas then arrow:SetAtlas("UI-HUD-RotationHelper-Active-2x",true) else arrow:SetTexture(ShapePath(p.shape)) end
        if custom and arrow.SetDesaturated then arrow:SetDesaturated(useColor) elseif arrow.SetDesaturated then arrow:SetDesaturated(false) end
        arrow:SetVertexColor(c[1],c[2],c[3],c[4]); arrow:SetRotation(custom and math.rad(p.rotation or 0) or 0); arrow:SetAlpha(shown and math.max(.35,p.opacity or 0) or 0)
        glow:ClearAllPoints(); glow:SetPoint("CENTER",arrow,"CENTER",0,0); glow:SetSize(size+14,size+14); glow:SetTexture(ShapePath(p.shape)); if glow.SetDesaturated then glow:SetDesaturated(true) end; glow:SetVertexColor(gc[1],gc[2],gc[3],gc[4]); glow:SetRotation(custom and math.rad(p.rotation or 0) or 0); glow:SetAlpha(custom and p.glow and (p.glowIntensity or .65) or 0)
        left:SetEnabled(custom); right:SetEnabled(custom); reset:SetEnabled(custom); left:SetAlpha(custom and 1 or .35); right:SetAlpha(custom and 1 or .35); reset:SetAlpha(custom and 1 or .35)
        info:SetText(custom and string.format("Scale %.2f  Rot %d  X %d  Y %d",p.scale or 1,p.rotation or 0,p.offsetX or 0,p.offsetY or 0) or (p.mode=="original" and "Blizzard original preview" or "Arrow hidden"))
    end)

    local size=HPanel(page,"3. Size & Opacity"); size:SetPoint("TOPLEFT",398,0); size:SetSize(252,170)
    HSlider(size,"Opacity",12,-34,225,0,100,1,function() return (Profile().opacity or 0)*100 end,function(v) Profile().opacity=v/100 end,function(v) return math.floor(v+.5).."%" end)
    HSlider(size,"Scale",12,-82,225,.5,2,.05,function() return Profile().scale or 1 end,function(v) Profile().scale=v end,nil,function() return Profile().mode=="custom" end)
    HSlider(size,"Rotation",12,-130,225,0,360,5,function() return Profile().rotation or 0 end,function(v) Profile().rotation=v end,function(v) return math.floor(v+.5).." deg" end,function() return Profile().mode=="custom" end)

    local shapes=HPanel(page,"4. Choose Shape (20)"); shapes:SetPoint("TOPLEFT",0,-175); shapes:SetSize(420,340)
    for index,shape in ipairs(SHAPES) do
        local shapeKey=shape
        local col=(index-1)%5
        local row=math.floor((index-1)/5)
        local b=CreateFrame("Button",nil,shapes,"BackdropTemplate")
        b:SetSize(72,58)
        b:SetPoint("TOPLEFT",14+col*80,-38-row*72)
        b:SetBackdrop({bgFile="Interface\Buttons\WHITE8X8",edgeFile="Interface\Tooltips\UI-Tooltip-Border",edgeSize=10})
        b:SetBackdropColor(.025,.035,.035,1)
        local tex=b:CreateTexture(nil,"ARTWORK")
        tex:SetSize(42,42)
        tex:SetPoint("TOP",0,-3)
        tex:SetTexture(ShapePath(shapeKey))
        tex:SetVertexColor(1,.77,.08,1)
        local num=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        num:SetPoint("BOTTOM",0,2)
        num:SetText(index)
        b:SetScript("OnClick",function() HSelectShape(shapeKey) end)
        b:SetScript("OnEnter",function(self)
            if Profile().mode~="custom" then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetText(SHAPE_LABELS[shapeKey],1,.82,0)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        HRegisterRefresh(function()
            local enabled=Profile().mode=="custom"
            b:SetEnabled(enabled)
            b:SetAlpha(enabled and 1 or .32)
            if enabled and Profile().shape==shapeKey then
                b:SetBackdropBorderColor(1,.72,.05,1)
                b:SetBackdropColor(.13,.09,.01,1)
            else
                b:SetBackdropBorderColor(.30,.30,.26,1)
                b:SetBackdropColor(.025,.035,.035,1)
            end
        end)
    end

    local color=HPanel(page,"5. Color"); color:SetPoint("TOPLEFT",425,-175); color:SetSize(225,202)
    local customMode=function() return Profile().mode=="custom" end
    local colorMode=function() local m=Profile().mode; return m=="custom" or m=="original" end
    HCheck(color,"Use Custom Arrow Color",10,-38,function() return Profile().colorEnabled~=false end,function(v) Profile().colorEnabled=v end,colorMode)
    local arrowColorEnabled=function() return colorMode() and Profile().colorEnabled~=false end
    local choose=HButton(color,"Choose Arrow Color",153,25); choose:SetPoint("TOPLEFT",12,-70); choose:SetScript("OnClick",function() if arrowColorEnabled() then OpenHCAAColorPicker("arrow") end end); local sw=HSwatch(color,172,-70,28,function() return Profile().color or {1,1,1,1} end); sw:SetScript("OnClick",function() if arrowColorEnabled() then OpenHCAAColorPicker("arrow") end end)
    local glowEnabled=function() return customMode() end
    HCheck(color,"Enable Glow",10,-107,function() return Profile().glow end,function(v) Profile().glow=v end,glowEnabled)
    local gb=HButton(color,"Glow Color",120,24); gb:SetPoint("TOPLEFT",12,-138); gb:SetScript("OnClick",function() if glowEnabled() then OpenHCAAColorPicker("glow") end end)
    local gs=HSwatch(color,142,-138,27,function() return Profile().glowColor or {1,.78,.05,1} end); gs:SetScript("OnClick",function() if glowEnabled() then OpenHCAAColorPicker("glow") end end)
    HRegisterRefresh(function()
        local ce=arrowColorEnabled()
        choose:SetEnabled(ce); choose:SetAlpha(ce and 1 or .45)
        sw:SetEnabled(ce); sw:SetAlpha(ce and 1 or .45)
        local enabled=glowEnabled()
        gb:SetEnabled(enabled); gb:SetAlpha(enabled and 1 or .45)
        gs:SetEnabled(enabled); gs:SetAlpha(enabled and 1 or .45)
    end)
    HSlider(color,"Glow Intensity",12,-172,190,0,100,1,function() return (Profile().glowIntensity or .65)*100 end,function(v) Profile().glowIntensity=v/100 end,function(v) return math.floor(v+.5).."%" end,glowEnabled)
    local anim=HPanel(page,"6. Animation"); anim:SetPoint("TOPLEFT",425,-410); anim:SetSize(225,105)
    HCheck(anim,"Pulse Animation",10,-31,function() return Profile().pulse end,function(v) Profile().pulse=v end); HCheck(anim,"Flash on Proc",10,-57,function() return Profile().flashOnProc end,function(v) Profile().flashOnProc=v end); HLabel(anim,"Pulse Speed",13,-88,"GameFontHighlight"); HDropdown(anim,92,-74,95,{{"Slow",.75},{"Medium",1.5},{"Fast",2.5}},function() local v=Profile().pulseSpeed or 1.5; if v<1.1 then return .75 elseif v>2 then return 2.5 end return 1.5 end,function(v) Profile().pulseSpeed=v end)
end

local function HBuildAppearance(owner,page)
    local visual=HPanel(page,"Visual Behavior"); visual:SetPoint("TOPLEFT",0,0); visual:SetSize(650,190)
    HCheck(visual,"Smooth fade",20,-45,function() return Profile().fade end,function(v) Profile().fade=v end)
    HSlider(visual,"Fade Duration",25,-88,280,.05,1.5,.05,function() return Profile().fadeDuration or .2 end,function(v) Profile().fadeDuration=v end,function(v) return string.format("%.2fs",v) end)
    HSlider(visual,"Arrow Scale",340,-45,275,.5,2,.05,function() return Profile().scale or 1 end,function(v) Profile().scale=v end,nil,function() return Profile().mode=="custom" end)
    HSlider(visual,"Arrow Rotation",340,-105,275,0,360,5,function() return Profile().rotation or 0 end,function(v) Profile().rotation=v end,function(v) return math.floor(v+.5).." deg" end,function() return Profile().mode=="custom" end)

    local pos=HPanel(page,"Frame Position"); pos:SetPoint("TOPLEFT",0,-200); pos:SetSize(650,145)
    HSlider(pos,"Horizontal (Left / Right)",22,-42,270,-80,80,1,function() return Profile().offsetX or 0 end,function(v) Profile().offsetX=v end,function(v) return math.floor(v+.5) end,function() return Profile().mode=="custom" end)
    HSlider(pos,"Vertical (Down / Up)",350,-42,270,-80,80,1,function() return Profile().offsetY or 0 end,function(v) Profile().offsetY=v end,function(v) return math.floor(v+.5) end,function() return Profile().mode=="custom" end)
    local resetFrame=HButton(pos,"Center Custom Frame",180,25); resetFrame:SetPoint("BOTTOMLEFT",22,14); resetFrame:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().offsetX=0; Profile().offsetY=0; ApplyCached(); RefreshConfig() end)

    local mini=HPanel(page,"Minimap Button"); mini:SetPoint("TOPLEFT",0,-355); mini:SetSize(650,150)
    HCheck(mini,"Show minimap button",20,-45,function() return not HCAA_DB.minimap.hide end,function(v) HCAA_DB.minimap.hide=not v; if minimapButton then minimapButton:SetShown(v) end end)
    HLabel(mini,"Left: options  |  Right: toggle  |  Middle: hide  |  Wheel: opacity  |  Drag: move",22,-88,"GameFontHighlightSmall",.75,.75,.75)
    local reset=HButton(mini,"Reset Minimap Position",190,25); reset:SetPoint("TOPLEFT",20,-110); reset:SetScript("OnClick",function() HCAA_DB.minimap.angle=225; if minimapButton and Minimap then local a=math.rad(225); minimapButton:ClearAllPoints(); minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*80,math.sin(a)*80) end; RefreshConfig() end)
end
local function HBuildRules(owner,page)
    local combat=HPanel(page,"Combat Rule"); combat:SetPoint("TOPLEFT",0,0); combat:SetSize(650,145)
    HLabel(combat,"Assistant arrow visibility during combat:",20,-45,"GameFontHighlight")
    HDropdown(combat,18,-66,260,{{"No combat rule","none"},{"Hide while in combat","hide_in_combat"},{"Show only in combat","show_in_combat"}},function() return Profile().autoCombat end,function(v) Profile().autoCombat=v end)
    local zones=HPanel(page,"Allowed Zones"); zones:SetPoint("TOPLEFT",0,-155); zones:SetSize(650,220)
    local zoneList={{"Solo / Open World","solo"},{"Dungeon","dungeon"},{"Raid","raid"},{"Arena","arena"},{"Battleground","battleground"}}
    for i,z in ipairs(zoneList) do local zoneLabel,zoneKey=z[1],z[2]; HCheck(zones,zoneLabel,25+((i-1)%2)*285,-45-math.floor((i-1)/2)*48,function() return Profile().zones[zoneKey]~=false end,function(v) Profile().zones[zoneKey]=v end) end
    local note=HPanel(page,"How Rules Work"); note:SetPoint("TOPLEFT",0,-385); note:SetSize(650,130)
    local t=HLabel(note,"A zone must be enabled and the combat rule must allow the arrow.\nRules are reevaluated on combat, zone, specialization, action-bar, and spell changes.",22,-46,"GameFontHighlight",.75,.75,.75); t:SetSpacing(6)
end
local function HBuildProfiles(owner,page)
    local box=HPanel(page,"Profile Scope"); box:SetPoint("TOPLEFT",0,0); box:SetSize(650,200)
    HLabel(box,"Store settings:",20,-48,"GameFontHighlight")
    HDropdown(box,18,-70,260,{{"Account-wide","account"},{"Per Character","character"},{"Per Specialization","spec"}},function() return HCAA_DB.profileMode or "account" end,function(v) HCAA_DB.profileMode=v end)
    local active=HLabel(box,"",22,-130,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B)
    HRegisterRefresh(function() local map={account="Account Profile",character=CharacterKey(),spec=SpecKey()}; active:SetText("Active: "..(map[HCAA_DB.profileMode] or "Account Profile")) end)
    local tools=HPanel(page,"Profile Tools"); tools:SetPoint("TOPLEFT",0,-210); tools:SetSize(650,190)
    local reset=HButton(tools,"Reset Current Profile",180,27); reset:SetPoint("TOPLEFT",22,-52); reset:SetScript("OnClick",function() local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); RefreshConfig(); Print("Current profile reset.") end)
    local copy=HButton(tools,"Copy Account Settings Here",210,27); copy:SetPoint("LEFT",reset,"RIGHT",18,0); copy:SetScript("OnClick",function() local source=HCAA_DB.profiles.account or {}; local target=Profile(); if target~=source then wipe(target); for k,v in pairs(DeepCopy(source)) do target[k]=v end; CopyDefaults(DEFAULT_PROFILE,target); ApplyCached(); RefreshConfig(); Print("Account settings copied.") end end)
    HLabel(tools,"Cancel restores the complete settings snapshot from when this window opened.",22,-110,"GameFontHighlightSmall",.75,.75,.75)
end
local function HBuildKeybinds(owner,page)
    local box=HPanel(page,"Toggle Keybind"); box:SetPoint("TOPLEFT",0,0); box:SetSize(650,240)
    HLabel(box,"Click the button, then press the key combination you want.",22,-48,"GameFontHighlight")
    local current=HLabel(box,"",22,-92,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B)
    local capture=HButton(box,"Set Toggle Key",190,32); capture:SetPoint("TOPLEFT",22,-128); local clear=HButton(box,"Clear Binding",150,32); clear:SetPoint("LEFT",capture,"RIGHT",16,0)
    local function refreshKey() local k1,k2=GetBindingKey("HCAA_TOGGLE"); current:SetText("Current: "..(k1 or k2 or "Not Bound")) end; HRegisterRefresh(refreshKey)
    capture:SetScript("OnClick",function(self) self:SetText("Press a key..."); self:EnableKeyboard(true); if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end end)
    capture:SetScript("OnKeyDown",function(self,key)
        if key=="ESCAPE" then self:EnableKeyboard(false); self:SetText("Set Toggle Key"); return end
        if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
        local combo=(IsControlKeyDown() and "CTRL-" or "")..(IsAltKeyDown() and "ALT-" or "")..(IsShiftKeyDown() and "SHIFT-" or "")..key
        SetBinding(combo,"HCAA_TOGGLE"); SaveBindings(GetCurrentBindingSet()); self:EnableKeyboard(false); self:SetText("Set Toggle Key"); refreshKey(); Print("Keybind set to "..combo..".")
    end)
    clear:SetScript("OnClick",function() local k1,k2=GetBindingKey("HCAA_TOGGLE"); if k1 then SetBinding(k1) end; if k2 then SetBinding(k2) end; SaveBindings(GetCurrentBindingSet()); refreshKey() end)
    local help=HPanel(page,"Slash Commands"); help:SetPoint("TOPLEFT",0,-250); help:SetSize(650,265)
    local text=HLabel(help,"/hcaa - Open options\n/hcaa on | off | toggle\n/hcaa opacity 0-100\n/hcaa mode hidden | original | custom (original: Blizzard UI only)\n/hcaa shape NAME\n/hcaa export | import | reset",24,-48,"GameFontHighlight"); text:SetSpacing(7)
end
local function HBuildStats(owner,page)
    local box=HPanel(page,"Statistics"); box:SetPoint("TOPLEFT",0,0); box:SetSize(650,260)
    local eventsText=HLabel(box,"",28,-65,"GameFontNormalHuge",GOLD_R,GOLD_G,GOLD_B); local timeText=HLabel(box,"",28,-135,"GameFontNormalLarge",.25,1,.55)
    HRegisterRefresh(function() local s=HCAA_DB.statistics or {}; eventsText:SetText(string.format("Hidden Events: %d",s.hiddenCount or 0)); local sec=s.hiddenSeconds or 0; timeText:SetText(string.format("Hidden Time: %dh %dm %ds",math.floor(sec/3600),math.floor((sec%3600)/60),sec%60)) end)
    local clear=HButton(box,"Clear Statistics",160,28); clear:SetPoint("BOTTOMLEFT",24,22); clear:SetScript("OnClick",function() HCAA_DB.statistics={hiddenCount=0,hiddenSeconds=0,lastStart=nil}; RefreshConfig(); Print("Statistics cleared.") end)
    local status=HPanel(page,"Current Status"); status:SetPoint("TOPLEFT",0,-270); status:SetSize(650,245); local text=HLabel(status,"",24,-50,"GameFontHighlight"); text:SetSpacing(8)
    HRegisterRefresh(function() local p=Profile(); local err=runtimeStatus.lastError and ("\nLast Error: "..runtimeStatus.lastError) or ""; text:SetText(string.format("Enabled: %s\nMode: %s\nShape: %s\nOpacity: %d%%\nTargets: %d (Blizzard %d / EllesmereUI %d / ElvUI %d)\nZone: %s\nDetected UI: %s%s",p.enabled and "Yes" or "No",p.mode,SHAPE_LABELS[p.shape] or p.shape,math.floor((p.opacity or 0)*100+.5),runtimeStatus.count or 0,runtimeStatus.blizzard or 0,runtimeStatus.ellesmere or 0,runtimeStatus.elvui or 0,ZoneType(),DetectedUI(),err)) end)
end
local function HBuildImport(owner,page)
    local ex=HPanel(page,"Export"); ex:SetPoint("TOPLEFT",0,0); ex:SetSize(650,205); HLabel(ex,"Create a portable HCAA profile string for the current profile.",22,-50,"GameFontHighlight"); local eb=HButton(ex,"Export Settings",190,30); eb:SetPoint("TOPLEFT",22,-92); eb:SetScript("OnClick",function() PopupEdit("Copy your HCAA profile:",ExportString()) end)
    local im=HPanel(page,"Import"); im:SetPoint("TOPLEFT",0,-215); im:SetSize(650,220); HLabel(im,"Paste an HCAA profile string.",22,-50,"GameFontHighlight"); local ib=HButton(im,"Import Settings",190,30); ib:SetPoint("TOPLEFT",22,-92); ib:SetScript("OnClick",function() PopupEdit("Paste an HCAA profile string:","",function(s) local ok,err=ImportString(s); Print(ok and "Profile imported." or err); RefreshConfig() end) end)
end
local function HBuildAbout(owner,page)
    local box=HPanel(page,"About HCAA"); box:SetPoint("TOPLEFT",0,0); box:SetSize(650,525)
    local icon=box:CreateTexture(nil,"ARTWORK"); icon:SetSize(82,82); icon:SetPoint("TOPLEFT",22,-44); icon:SetTexture("Interface\\AddOns\\HCAA\\icon")
    HLabel(box,"Hide And Customize Assistant Arrow",122,-48,"GameFontNormalHuge",GOLD_R,GOLD_G,GOLD_B)
    HLabel(box,"Version "..VERSION,124,-84,"GameFontHighlight",.25,1,.55)
    HLabel(box,"Author: FaneyQ8",124,-110,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B)
    local desc=HLabel(box,"Customize Blizzard's Single-Button Assistant Arrow with custom frames, colors, glow, profiles and automatic rules.",22,-148,"GameFontHighlight")
    desc:SetWidth(600); desc:SetJustifyH("LEFT")

    HLabel(box,"Social & Support",22,-196,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B)
    local function SocialIcon(key,x)
        local data=SOCIAL[key]
        local b=CreateFrame("Button",nil,box,"BackdropTemplate")
        b:SetSize(54,54); b:SetPoint("TOPLEFT",x,-228)
        b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
        b:SetBackdropColor(.015,.015,.015,.96); b:SetBackdropBorderColor(.75,.58,.12,1)
        local tx=b:CreateTexture(nil,"ARTWORK"); tx:SetPoint("TOPLEFT",7,-7); tx:SetPoint("BOTTOMRIGHT",-7,7); tx:SetTexture(data.icon)
        b:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:SetText(data.label,1,.82,0)
            GameTooltip:AddLine(data.value,.85,.85,.85,true)
            GameTooltip:AddLine("Click to copy",.25,1,.55)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        b:SetScript("OnClick",function() PopupEdit(data.label..":",data.value) end)
    end
    local order={"twitch","tiktok","discord","battlenet","github","donate"}
    for i,key in ipairs(order) do SocialIcon(key,22+(i-1)*94) end
    HLabel(box,"Click an icon to copy its link or account name.",22,-292,"GameFontHighlightSmall",.75,.75,.75)

    local status=HPanel(box,"Current Build"); status:SetPoint("TOPLEFT",18,-326); status:SetSize(614,155)
    local st=HLabel(status,"",20,-46,"GameFontHighlight"); st:SetSpacing(7); st:SetWidth(570)
    HRegisterRefresh(function()
        local p=Profile()
        st:SetText(string.format("Mode: %s    Shape: %s    Opacity: %d%%\nDetected UI: %s\nActive Assistant Buttons: %d",
            p.mode,SHAPE_LABELS[p.shape] or p.shape,math.floor((p.opacity or 0)*100+.5),DetectedUI(),(runtimeStatus.ellesmere or 0)+(runtimeStatus.elvui or 0)+(runtimeStatus.blizzard or 0)))
    end)
end

local function HBuildSidePreview(owner)
    local side=CreateFrame("Frame",nil,owner); side:SetPoint("TOPLEFT",828,-42); side:SetSize(260,525)
    local game=HPanel(side,"In-Game Preview"); game:SetPoint("TOPLEFT",0,0); game:SetSize(260,335); owner.sideGamePreview=game
    local scene=CreateFrame("Frame",nil,game,"BackdropTemplate"); scene:SetPoint("TOPLEFT",12,-38); scene:SetSize(236,205); scene:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10}); scene:SetBackdropColor(0,.10,.10,.95)
    local icons={"Interface\\Icons\\Spell_Fire_FlameBolt","Interface\\Icons\\Spell_Frost_FrostBolt02","Interface\\Icons\\Ability_Creature_Cursed_03","Interface\\Icons\\INV_Misc_QuestionMark"}; local slots={}
    for i=1,4 do local s=CreateFrame("Frame",nil,scene,"BackdropTemplate"); s:SetSize(60,60); local x=(i==1 or i==3) and 42 or 125; local y=(i<=2) and -28 or -112; s:SetPoint("TOPLEFT",x,y); s:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=11}); s:SetBackdropColor(.02,.03,.03,1); s:SetBackdropBorderColor(.35,.35,.35,1); local icon=s:CreateTexture(nil,"ARTWORK"); icon:SetPoint("TOPLEFT",5,-5); icon:SetPoint("BOTTOMRIGHT",-5,5); icon:SetTexture(icons[i]); icon:SetTexCoord(.08,.92,.08,.92); if i==4 then icon:SetDesaturated(true) end; local key=s:CreateFontString(nil,"OVERLAY","GameFontNormal"); key:SetPoint("TOPRIGHT",-5,-4); key:SetText(i==1 and "F1" or (i==2 and "F2" or tostring(i-2))); slots[i]=s end
    local pg=scene:CreateTexture(nil,"OVERLAY",nil,6); pg:SetPoint("CENTER",slots[1],"CENTER"); pg:SetBlendMode("ADD"); local pa=scene:CreateTexture(nil,"OVERLAY",nil,7); pa:SetPoint("CENTER",slots[1],"CENTER"); local status=scene:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); status:SetPoint("TOPLEFT",8,-7)
    HLabel(game,"Tips:",14,-253,"GameFontNormal",GOLD_R,GOLD_G,GOLD_B); HLabel(game,"- Mouse wheel changes opacity.\n- Middle click hides the arrow.\n- Drag the minimap button to move it.",18,-276,"GameFontHighlightSmall",.78,.78,.78)
    local mini=HPanel(side,"Minimap Button"); mini:SetPoint("TOPLEFT",0,-345); mini:SetSize(260,180); owner.sideMinimapPreview=mini; local mi=mini:CreateTexture(nil,"ARTWORK"); mi:SetSize(74,74); mi:SetPoint("TOPLEFT",15,-48); mi:SetTexture("Interface\\AddOns\\HCAA\\icon"); HLabel(mini,"Left:     Open Options\nMiddle: Hide / Show\nWheel:   Opacity +/-\nDrag:     Move Button",100,-50,"GameFontHighlightSmall",.88,.88,.88)
    HRegisterRefresh(function()
        local p=Profile(); local useColor=p.colorEnabled~=false; local c=useColor and (p.color or {1,1,1,1}) or {1,1,1,1}; local gc=p.glowColor or {1,.78,.05,1}; local custom=p.mode=="custom"; local shown=p.mode~="hidden"
        local sz=custom and Clamp(78*(p.scale or 1),55,115) or 78
        pa:ClearAllPoints(); pa:SetPoint("CENTER",slots[1],"CENTER",p.offsetX or 0,p.offsetY or 0); pa:SetSize(sz,sz)
        if p.mode=="original" and pa.SetAtlas then pa:SetAtlas("UI-HUD-RotationHelper-Active-2x",true) else pa:SetTexture(ShapePath(p.shape)) end
        if custom and pa.SetDesaturated then pa:SetDesaturated(useColor) elseif pa.SetDesaturated then pa:SetDesaturated(false) end
        pa:SetVertexColor(c[1],c[2],c[3],c[4]); pa:SetRotation(custom and math.rad(p.rotation or 0) or 0); pa:SetAlpha(shown and math.max(.35,p.opacity or 0) or 0)
        pg:ClearAllPoints(); pg:SetPoint("CENTER",pa,"CENTER",0,0); pg:SetSize(sz+14,sz+14); pg:SetTexture(ShapePath(p.shape)); if pg.SetDesaturated then pg:SetDesaturated(true) end; pg:SetVertexColor(gc[1],gc[2],gc[3],gc[4]); pg:SetRotation(custom and math.rad(p.rotation or 0) or 0); pg:SetAlpha(custom and p.glow and (p.glowIntensity or .65) or 0)
        status:SetText(string.format("%s - %d%%",p.mode,math.floor((p.opacity or 0)*100+.5)))
    end)
end
local function HBuildShapeStrip(owner)
    local strip=HPanel(owner,"All 20 Shapes Preview"); strip:SetPoint("TOPLEFT",170,-575); strip:SetSize(918,100)
    for index,shape in ipairs(SHAPES) do local shapeKey=shape; local col=(index-1)%10; local row=math.floor((index-1)/10); local b=CreateFrame("Button",nil,strip,"BackdropTemplate"); b:SetSize(80,30); b:SetPoint("TOPLEFT",16+col*89,-34-row*31); b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8}); b:SetBackdropColor(.015,.025,.025,1); local tex=b:CreateTexture(nil,"ARTWORK"); tex:SetSize(28,28); tex:SetPoint("LEFT",4,0); tex:SetTexture(ShapePath(shapeKey)); tex:SetVertexColor(1,.77,.08,1); local num=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); num:SetPoint("LEFT",tex,"RIGHT",4,0); num:SetText(index); b:SetScript("OnClick",function() HSelectShape(shapeKey) end); HRegisterRefresh(function() if Profile().shape==shapeKey then b:SetBackdropBorderColor(1,.72,.05,1) else b:SetBackdropBorderColor(.27,.27,.24,1) end end) end
end

local function CreateModernConfig()
    local f=CreateFrame("Frame","HCAAConfigFrameModern",UIParent,"BasicFrameTemplateWithInset"); f:SetSize(1100,620); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide(); f.refreshers={}; hBuildingConfig=f
    f.TitleText:SetText("HCAA v"..VERSION.." - Hide And Customize Assistant Arrow"); f.TitleText:SetTextColor(GOLD_R,GOLD_G,GOLD_B)
    local nav=HPanel(f); nav:SetPoint("TOPLEFT",12,-42); nav:SetSize(150,525)
    local tabs={{"General","Interface\\Icons\\INV_Misc_Gear_01",HBuildGeneral},{"Appearance","Interface\\Icons\\INV_Misc_Gem_01",HBuildAppearance},{"Auto Rules","Interface\\Icons\\Ability_DualWield",HBuildRules},{"Profiles","Interface\\Icons\\INV_Misc_GroupLooking",HBuildProfiles},{"Keybinds","Interface\\Icons\\INV_Misc_Key_04",HBuildKeybinds},{"Stats","Interface\\Icons\\INV_Misc_Note_06",HBuildStats},{"Import / Export","Interface\\Icons\\INV_Misc_Book_09",HBuildImport},{"About","Interface\\Icons\\INV_Misc_QuestionMark",HBuildAbout}}
    f.pages={}; f.tabButtons={}
    function f:ShowTab(index)
        self.activeTab=index
        for i,p in ipairs(self.pages) do
            p:SetShown(i==index)
            local b=self.tabButtons[i]
            if i==index then
                b:SetBackdropColor(.16,.11,.015,1); b:SetBackdropBorderColor(1,.72,.05,1); b.label:SetTextColor(1,.88,.45)
            else
                b:SetBackdropColor(.015,.025,.025,.9); b:SetBackdropBorderColor(.22,.22,.20,1); b.label:SetTextColor(.88,.88,.88)
            end
        end
        if self.sideGamePreview then self.sideGamePreview:SetShown(index==2) end
        if self.sideMinimapPreview then
            self.sideMinimapPreview:ClearAllPoints()
            -- sideMinimapPreview is parented to the side column, so coordinates
            -- must be local to that column. Using 828 here moved it off-screen.
            if index==2 then
                self.sideMinimapPreview:SetPoint("TOPLEFT",0,-345)
            else
                self.sideMinimapPreview:SetPoint("TOPLEFT",0,0)
            end
        end
        RefreshConfig()
    end
    for i,tab in ipairs(tabs) do local tabIndex=i; local b=CreateFrame("Button",nil,nav,"BackdropTemplate"); b:SetSize(132,52); b:SetPoint("TOPLEFT",8,-10-(i-1)*58); b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=9}); local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(28,28); icon:SetPoint("LEFT",8,0); icon:SetTexture(tab[2]); icon:SetTexCoord(.08,.92,.08,.92); local label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); label:SetPoint("LEFT",icon,"RIGHT",8,0); label:SetText(tab[1]); b.label=label; b:SetScript("OnClick",function() f:ShowTab(tabIndex) end); f.tabButtons[i]=b; local page=CreateFrame("Frame",nil,f); page:SetPoint("TOPLEFT",170,-42); page:SetSize(650,525); page:Hide(); f.pages[i]=page; tab[3](f,page) end
    HBuildSidePreview(f)
    local reset=HButton(f,"Reset to Default",180,28); reset:SetPoint("BOTTOMLEFT",195,12); reset:SetScript("OnClick",function() local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); RefreshConfig() end)
    local cancel=HButton(f,"Cancel",190,28); cancel:SetPoint("BOTTOMRIGHT",-220,12); local okay=HButton(f,"Okay",190,28); okay:SetPoint("BOTTOMRIGHT",-20,12)
    function f:CancelChanges() if self.snapshot then wipe(HCAA_DB); for k,v in pairs(DeepCopy(self.snapshot)) do HCAA_DB[k]=v end end; ApplyCached(); self:Hide() end
    cancel:SetScript("OnClick",function() f:CancelChanges() end); f.CloseButton:SetScript("OnClick",function() f:CancelChanges() end); okay:SetScript("OnClick",function() f.snapshot=DeepCopy(HCAA_DB); f:Hide() end)
    hBuildingConfig=nil; configFrame=f; f:ShowTab(1)
end
RefreshConfig=function() if configFrame and configFrame:IsShown() then for _,fn in ipairs(configFrame.refreshers or {}) do fn() end end end
OpenConfig=function() if not configFrame or not configFrame.refreshers then CreateModernConfig() end; if configFrame:IsShown() then configFrame:CancelChanges() else configFrame.snapshot=DeepCopy(HCAA_DB); configFrame:Show(); RefreshConfig() end end

local function UpdateMinimapPosition()
    if not minimapButton or not Minimap then return end local a=math.rad(HCAA_DB.minimap.angle or 225); minimapButton:ClearAllPoints(); minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*80,math.sin(a)*80)
end
local function CreateMinimap()
    if minimapButton or not Minimap then return end
    local b=CreateFrame("Button","HCAAMinimapButton",Minimap); b:SetSize(32,32); b:SetFrameStrata("MEDIUM"); b:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp"); b:EnableMouseWheel(true); b:RegisterForDrag("LeftButton")
    local i=b:CreateTexture(nil,"BACKGROUND"); i:SetTexture("Interface\\AddOns\\HCAA\\icon"); i:SetSize(22,22); i:SetPoint("CENTER"); b.icon=i
    local border=b:CreateTexture(nil,"OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54,54); border:SetPoint("TOPLEFT")
    b:SetScript("OnDragStart",function(self) self:SetScript("OnUpdate",function() local mx,my=Minimap:GetCenter(); local sc=Minimap:GetEffectiveScale(); local x,y=GetCursorPosition(); x,y=x/sc,y/sc; HCAA_DB.minimap.angle=math.deg(math.atan2(y-my,x-mx)); UpdateMinimapPosition() end) end); b:SetScript("OnDragStop",function(self) self:SetScript("OnUpdate",nil) end)
    b:SetScript("OnClick",function(_,btn) if btn=="RightButton" then SetEnabled(not Profile().enabled) elseif btn=="MiddleButton" then SetOpacity(0) else OpenConfig() end end)
    b:SetScript("OnMouseWheel",function(_,d) local v=Clamp(math.floor((Profile().opacity or 0)*100+.5)+(d>0 and 5 or -5),0,100); SetOpacity(v/100); Print("Opacity: "..v.."%") end)
    b:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:AddLine("HCAA v"..VERSION,1,.82,0); GameTooltip:AddDoubleLine("UI",DetectedUI()); GameTooltip:AddDoubleLine("Mode",Profile().mode); GameTooltip:AddDoubleLine("Shape",SHAPE_LABELS[Profile().shape] or "Original"); GameTooltip:AddDoubleLine("Opacity",math.floor((Profile().opacity or 0)*100).."%"); GameTooltip:AddLine(" "); GameTooltip:AddLine("Left: Settings | Right: Toggle | Middle: Hide | Wheel: Opacity | Drag: Move",.8,.8,.8); GameTooltip:Show() end); b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    minimapButton=b; UpdateMinimapPosition(); if HCAA_DB.minimap.hide then b:Hide() end
end

function HCAA_ToggleBinding() SetEnabled(not Profile().enabled) end
BINDING_HEADER_HCAA="HCAA"
BINDING_NAME_HCAA_TOGGLE="Toggle HCAA"

SLASH_HCAA1="/hcaa"
SlashCmdList.HCAA=function(msg)
    local raw=(msg or ""):match("^%s*(.-)%s*$"); local low=raw:lower()
    if low=="" then OpenConfig() elseif low=="on" then SetEnabled(true) elseif low=="off" then SetEnabled(false) elseif low=="toggle" then SetEnabled(not Profile().enabled)
    elseif low=="export" then PopupEdit("Copy your HCAA profile:",ExportString()) elseif low=="import" then PopupEdit("Paste HCAA profile:","",function(s) local ok,e=ImportString(s); Print(ok and "Imported." or e) end)
    elseif low=="reset" then local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); Print("Profile reset.")
    else
        local o=low:match("^opacity%s+(%d+)$"); local m=low:match("^mode%s+(%a+)$"); local sh=low:match("^shape%s+([%w_]+)$")
        if o then SetOpacity(Clamp(o,0,100)/100) elseif m then SetMode(m) elseif sh and (VALID_SHAPES[sh] or LEGACY_SHAPE_MAP[sh]) then Profile().shape=NormalizeShape(sh); Profile().mode="custom"; ApplyCached() else Print("Commands: /hcaa on|off|toggle|opacity 0-100|mode hidden/original/custom|shape NAME|export|import|reset") end
    end
end

local function FirstRun()
    if not HCAA_DB.firstRun then return end HCAA_DB.firstRun=false
    StaticPopupDialogs.HCAA_WELCOME={text="Welcome to HCAA v"..VERSION.."!\n\nChoose a starting mode. You can customize 20 shapes, colors, rules and profiles from the minimap button.",button1="Hide Arrow",button2="Customize",button3="Keep Original",timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function() SetMode("hidden") end, OnCancel=function() SetMode("custom"); OpenConfig() end, OnAlt=function() if IsEllesmereUI() then SetMode("custom"); OpenConfig() else SetMode("original") end end}
    StaticPopup_Show("HCAA_WELCOME")
end
StartPulseTicker=function()
    StopPulseTicker()
    local p=Profile()
    if not p.enabled or not p.pulse or p.mode~="custom" then return end
    local t=0
    pulseTicker=C_Timer.NewTicker(.10,function()
        local current=Profile()
        if not current.enabled or not current.pulse or current.mode~="custom" then StopPulseTicker(); return end
        t=t+.10*(current.pulseSpeed or 1.5)
        local mul=.75+.25*math.sin(t*math.pi*2)
        local base=EffectiveAlpha()
        for owner,overlay in pairs(customOverlays) do
            if overlay and overlay.SetAlpha and overlay:IsShown() then
                overlay:SetAlpha(base*mul)
                local g=glowOverlays[overlay]
                if g and g:IsShown() then g:SetAlpha(Clamp(base*(current.glowIntensity or .65)*mul,0,1)) end
            elseif not overlay then
                customOverlays[owner]=nil
            end
        end
    end)
end

local actionBarRescanGeneration=0
local moveWatchTicker
local hookedEABButtons=setmetatable({}, {__mode="k"})
-- Track an actual Assistant-button drag between EllesmereUI bars.  EllesmereUI
-- reuses prebuilt arrow textures on every slot, so scanning textures alone cannot
-- identify the destination after a move.  We therefore remember that the source
-- was a currently managed Assistant button and explicitly adopt the destination
-- button that receives that drag.
local assistantMovePending=false
local assistantMoveSource=nil
local assistantMoveDestination=nil
local assistantMoveTimeout=nil
local function ResetEllesmereTracking()
    for button in pairs(activeEllesmereOwners) do
        HideCustomOverlay(button)
        activeEllesmereOwners[button]=nil
        ellesmereOwners[button]=nil
    end
end

local function CancelAssistantMoveTimeout()
    if assistantMoveTimeout then assistantMoveTimeout:Cancel(); assistantMoveTimeout=nil end
end

local function BeginAssistantMove(button)
    if not button then return end
    local overlay=customOverlays[button]
    local isManaged=activeEllesmereOwners[button] or ellesmereOwners[button] or (overlay and overlay:IsShown())
    if not isManaged then return end
    assistantMovePending=true
    assistantMoveSource=button
    assistantMoveDestination=nil
    HideCustomOverlay(button)
    activeEllesmereOwners[button]=nil
    ellesmereOwners[button]=nil
    CancelAssistantMoveTimeout()
    assistantMoveTimeout=C_Timer.NewTimer(4,function()
        assistantMoveTimeout=nil
        if assistantMovePending then
            assistantMovePending=false
            assistantMoveSource=nil
            assistantMoveDestination=nil
            ScheduleActionBarRescanBurst()
        end
    end)
end

local function CompleteAssistantMove(button)
    if not assistantMovePending or not button then return false end
    assistantMovePending=false
    assistantMoveDestination=button
    CancelAssistantMoveTimeout()

    -- Remove stale ownership, then explicitly seed the destination.  The action
    -- attribute may update a frame or two after OnReceiveDrag, but its template
    -- textures already exist, so ProcessEllesmereOwner can attach immediately.
    ResetEllesmereTracking()
    activeEllesmereOwners[button]=true
    ellesmereOwners[button]=true
    local ok,err=pcall(ProcessEllesmereOwner,button)
    if not ok and RecordScanError then RecordScanError("EllesmereUI moved owner",err) end

    local generation=actionBarRescanGeneration+1
    actionBarRescanGeneration=generation
    for _,delay in ipairs({0,0.03,0.08,0.16,0.35,0.70,1.25}) do
        C_Timer.After(delay,function()
            if not HCAA_DB or generation~=actionBarRescanGeneration then return end
            activeEllesmereOwners[button]=true
            ellesmereOwners[button]=true
            local ok2,err2=pcall(ProcessEllesmereOwner,button)
            if not ok2 and RecordScanError then RecordScanError("EllesmereUI move settle",err2) end
            if ok2 and Profile().mode=="original" then ApplyCached() end
        end)
    end
    assistantMoveSource=nil
    return true
end

local actionMoveHooksInstalled=false
local function FindEllesmereButtonForSlot(slot)
    slot=tonumber(slot)
    if not slot then return nil end
    for i=1,300 do
        local button=_G["EABButton"..i]
        if button and GetButtonActionSlot(button)==slot then return button end
    end
end

local function InstallActionMoveHooks()
    if actionMoveHooksInstalled or not hooksecurefunc then return end
    actionMoveHooksInstalled=true
    if type(PickupAction)=="function" then
        hooksecurefunc("PickupAction",function(slot)
            -- Blizzard's default action bars can rebuild the Assistant Rotation
            -- frame a few frames after pickup. Start the same short event-driven
            -- rescan burst used for EllesmereUI so Custom mode is reattached to
            -- the destination without requiring /reload.
            ScheduleActionBarRescanBurst()
            local button=FindEllesmereButtonForSlot(slot)
            if button and (activeEllesmereOwners[button] or ellesmereOwners[button] or ButtonHasAssistantAction(button)) then
                BeginAssistantMove(button)
            end
        end)
    end
    if type(PlaceAction)=="function" then
        hooksecurefunc("PlaceAction",function(slot)
            -- Always rescan after placing an action. For Blizzard UI this is the
            -- reliable signal that the Single-Button Assistant moved; the native
            -- ACTIONBAR_SLOT_CHANGED event can fire before its visual frame exists.
            ScheduleActionBarRescanBurst()
            if not assistantMovePending then return end
            local targetSlot=tonumber(slot)
            for _,delay in ipairs({0,0.02,0.06,0.12,0.25,0.50}) do
                C_Timer.After(delay,function()
                    if not assistantMovePending then return end
                    local button=FindEllesmereButtonForSlot(targetSlot)
                    if button and button~=assistantMoveSource then CompleteAssistantMove(button) end
                end)
            end
            C_Timer.After(.65,function()
                if assistantMovePending then ScheduleActionBarRescanBurst() end
            end)
        end)
    end
end

local function HookEllesmereButtons()
    InstallActionMoveHooks()
    for i=1,300 do
        local button=_G["EABButton"..i]
        if button and not hookedEABButtons[button] and button.HookScript then
            hookedEABButtons[button]=true
            button:HookScript("OnDragStart",function(self)
                BeginAssistantMove(self)
            end)
            button:HookScript("OnMouseDown",function(self)
                -- Some click-to-pickup configurations do not fire OnDragStart.
                -- Mark the move only when this is an already managed Assistant slot.
                if activeEllesmereOwners[self] or ellesmereOwners[self] then
                    BeginAssistantMove(self)
                end
            end)
            button:HookScript("OnReceiveDrag",function(self)
                if assistantMovePending and self~=assistantMoveSource and CompleteAssistantMove(self) then return end
                ScheduleActionBarRescanBurst()
            end)
            button:HookScript("OnMouseUp",function(self)
                if assistantMovePending and self~=assistantMoveSource and CompleteAssistantMove(self) then return end
                ScheduleActionBarRescanBurst()
            end)
            button:HookScript("OnShow",function() ScheduleActionBarRescanBurst() end)
            button:HookScript("OnAttributeChanged",function(self,name)
                if name=="action" or name=="type" then
                    if assistantMoveDestination==self then
                        activeEllesmereOwners[self]=true
                        C_Timer.After(0,function()
                            if HCAA_DB then pcall(ProcessEllesmereOwner,self) end
                        end)
                    else
                        ScheduleActionBarRescanBurst()
                    end
                end
            end)
        end
    end
end

function ScheduleActionBarRescanBurst()
    actionBarRescanGeneration=actionBarRescanGeneration+1
    local generation=actionBarRescanGeneration
    local preservedDestination=assistantMoveDestination
    ResetEllesmereTracking()
    if preservedDestination then
        activeEllesmereOwners[preservedDestination]=true
        ellesmereOwners[preservedDestination]=true
    end
    HookEllesmereButtons()
    if moveWatchTicker then moveWatchTicker:Cancel(); moveWatchTicker=nil end
    local elapsed=0
    moveWatchTicker=C_Timer.NewTicker(0.10,function(ticker)
        if generation~=actionBarRescanGeneration or not HCAA_DB then ticker:Cancel(); if moveWatchTicker==ticker then moveWatchTicker=nil end; return end
        elapsed=elapsed+0.10
        ScanAll()
        if elapsed>=3.0 then ticker:Cancel(); if moveWatchTicker==ticker then moveWatchTicker=nil end end
    end)
end

-- EllesmereUI rebuilds its action bars after PLAYER_LOGIN / PLAYER_ENTERING_WORLD.
-- A single early scan can bind HCAA to frames that EllesmereUI removes a moment later.
-- Use a small, finite set of delayed rescans so the custom frame reattaches to the
-- final action-button frames without a permanent ticker or /reload requirement.
local postReloadReattachGeneration=0
local function SchedulePostReloadReattach()
    if not IsEllesmereUI() then return end
    postReloadReattachGeneration=postReloadReattachGeneration+1
    local generation=postReloadReattachGeneration

    -- EllesmereUI rebuilds its action bars after /reload. Merely setting
    -- profile.enabled=true is not enough because cached targets can still point to
    -- frames that EllesmereUI has already replaced. Perform one real OFF -> ON cycle
    -- after the bars have had time to settle, exactly like running /hcaa off then
    -- /hcaa on, and then use a few lightweight rescans to attach to the final frames.
    C_Timer.After(1.00,function()
        if generation~=postReloadReattachGeneration or not HCAA_DB then return end
        SetEnabled(false)
        C_Timer.After(0.08,function()
            if generation~=postReloadReattachGeneration or not HCAA_DB then return end
            HookEllesmereButtons()
            SetEnabled(true)
            local ok,err=pcall(ScanAll)
            if not ok and RecordScanError then RecordScanError("EllesmereUI forced post-reload enable",err) end
            ScheduleActionBarRescanBurst()
        end)
    end)

    for _,delay in ipairs({1.35,1.80,2.40,3.20}) do
        C_Timer.After(delay,function()
            if generation~=postReloadReattachGeneration or not HCAA_DB then return end
            HookEllesmereButtons()
            local ok,err=pcall(ScanAll)
            if not ok and RecordScanError then RecordScanError("EllesmereUI post-reload reattach",err) end
            if RefreshConfig then RefreshConfig() end
        end)
    end
end

local events=CreateFrame("Frame"); for _,e in ipairs({"ADDON_LOADED","PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","ZONE_CHANGED_NEW_AREA","PLAYER_SPECIALIZATION_CHANGED","PLAYER_TALENT_UPDATE","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","ACTIONBAR_SHOWGRID","ACTIONBAR_HIDEGRID","UPDATE_BINDINGS","CURSOR_CHANGED","SPELLS_CHANGED"}) do events:RegisterEvent(e) end
events:SetScript("OnEvent",function(_,event,arg)
    if event=="ADDON_LOADED" and arg==ADDON_NAME then HCAA_DB=MigrateDatabase(HCAA_DB); return end
    if event=="ADDON_LOADED" and (arg=="ElvUI" or arg=="ElvUI_Libraries") then
        C_Timer.After(0.25,function() if HCAA_DB then InstallElvUIHooks(); ScanAll() end end)
    end
    if event=="PLAYER_LOGIN" then CreateMinimap(); FirstRun(); InstallElvUIHooks(); SchedulePostReloadReattach(); C_Timer.After(0.75,function() if HCAA_DB then InstallElvUIHooks(); ScanAll() end end) end
    if event=="PLAYER_ENTERING_WORLD" then SchedulePostReloadReattach() end
    if event=="ACTIONBAR_SLOT_CHANGED" or event=="ACTIONBAR_PAGE_CHANGED" or event=="ACTIONBAR_SHOWGRID" or event=="ACTIONBAR_HIDEGRID" or event=="CURSOR_CHANGED" then
        ScheduleActionBarRescanBurst()
    else
        ScheduleScan(event=="PLAYER_LOGIN" and .20 or .05)
    end
end)
hiddenTicker=C_Timer.NewTicker(5,function() local s=HCAA_DB and HCAA_DB.statistics; if s and s.lastStart then s.hiddenSeconds=(s.hiddenSeconds or 0)+5; s.lastStart=time() end end)
