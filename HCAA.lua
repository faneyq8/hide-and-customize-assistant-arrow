local ADDON_NAME = ...
local VERSION = "1.5.1"
local SOCIAL = {
    twitch={label="Twitch", value="https://www.twitch.tv/gamerzoneq8", icon="Interface\\AddOns\\HCAA\\Social\\twitch"},
    tiktok={label="TikTok", value="https://www.tiktok.com/@gamerzoneq8", icon="Interface\\AddOns\\HCAA\\Social\\tiktok"},
    discord={label="Discord", value=".faney", icon="Interface\\AddOns\\HCAA\\Social\\discord"},
    battlenet={label="Battle.net", value="Faney#2957", icon="Interface\\AddOns\\HCAA\\Social\\battlenet"},
    github={label="GitHub", value="https://github.com/faneyq8", icon="Interface\\AddOns\\HCAA\\Social\\github"},
}
BINDING_HEADER_HCAA = "HCAA"
BINDING_NAME_HCAA_TOGGLE = "Toggle HCAA"

local CLASSIC_SHAPES = {
    "skull_ring", "circle", "star", "shield", "diamond", "rune", "wings",
    "flame", "lightning", "moon", "compass", "sword", "crown", "crystal",
    "sun", "void", "hexagon", "triangle", "cross", "minimal_ring",
}
local MIDNIGHT_SHAPES = {
    "apex", "death_knight", "demon_hunter", "dreamrift", "druid",
    "evoker", "harandar", "hunter", "mage", "monk",
    "paladin", "priest", "rogue", "shaman", "silvermoon",
    "sunwell", "voidstorm", "warlock", "warrior", "zulaman",
}
local SHAPES = {}
for _,shape in ipairs(CLASSIC_SHAPES) do SHAPES[#SHAPES+1]=shape end
for _,shape in ipairs(MIDNIGHT_SHAPES) do SHAPES[#SHAPES+1]=shape end
local SHAPE_LABELS = {
    skull_ring="Skull Ring", circle="Circle", star="Star", shield="Shield", diamond="Diamond",
    rune="Rune", wings="Wings", flame="Flame", lightning="Lightning", moon="Moon",
    compass="Compass", sword="Sword", crown="Crown", crystal="Crystal", sun="Sun",
    void="Void", hexagon="Hexagon", triangle="Triangle", cross="Cross", minimal_ring="Minimal Ring",
    apex="Apex", death_knight="Death Knight", demon_hunter="Demon Hunter", dreamrift="Dreamrift",
    druid="Druid", evoker="Evoker", harandar="Harandar", hunter="Hunter", mage="Mage",
    monk="Monk", paladin="Paladin", priest="Priest", rogue="Rogue", shaman="Shaman",
    silvermoon="Silvermoon", sunwell="Sunwell", voidstorm="Voidstorm", warlock="Warlock",
    warrior="Warrior", zulaman="Zul'Aman",
}
local VALID_SHAPES = {}; for _,shape in ipairs(SHAPES) do VALID_SHAPES[shape]=true end
local MIDNIGHT_SHAPE_SET = {}; for _,shape in ipairs(MIDNIGHT_SHAPES) do MIDNIGHT_SHAPE_SET[shape]=true end
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
    fade=true, fadeDuration=0.20,
    autoCombat="none", zones={solo=true,dungeon=true,raid=true,arena=true,battleground=true},
}
local DEFAULTS = {
    schemaVersion=3, profileMode="account", minimap={hide=false,angle=225}, firstRun=true,
    profiles={account={}}, characterProfiles={}, specProfiles={}, statistics={hiddenCount=0,hiddenSeconds=0,lastStart=nil},
}

local managed = setmetatable({}, {__mode="k"})
local arrowTextures = setmetatable({}, {__mode="k"})
local original = setmetatable({}, {__mode="k"})
local hooked = setmetatable({}, {__mode="k"})
local minimapButton, configFrame, RefreshConfig, OpenConfig
local colorFrame
local NormalizeModeForUI
local hiddenTicker
local ScanAll, ApplyCached, ScheduleScan
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
    -- v1.5 removes obsolete animation settings while preserving all visual and scope data.
    profile.pulse=nil; profile.pulseSpeed=nil; profile.flashOnProc=nil
    return profile
end
local function MigrateDatabase(db)
    db=CopyDefaults(DEFAULTS,type(db)=="table" and db or {})
    db.profiles.account=MigrateProfile(db.profiles.account)
    for key,profile in pairs(db.characterProfiles) do db.characterProfiles[key]=MigrateProfile(profile) end
    for key,profile in pairs(db.specProfiles) do db.specProfiles[key]=MigrateProfile(profile) end
    db.schemaVersion=3
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
local function ShapePath(shape)
    shape=NormalizeShape(shape)
    local folder=MIDNIGHT_SHAPE_SET[shape] and "MidnightShapes" or "Shapes"
    return "Interface\\AddOns\\HCAA\\"..folder.."\\"..shape
end
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
    glow:SetAlpha(Clamp(EffectiveAlpha()*(p.glowIntensity or .65)*(multiplier or 1),0,1))
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
ApplyCached=function()
    if not HCAA_DB then return end
    local p=Profile()
    if not p.enabled then
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


local function PopupEdit(title,text,onAccept)
    StaticPopupDialogs.HCAA_EDIT={text=title,button1=ACCEPT,button2=CANCEL,hasEditBox=true,editBoxWidth=420,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnShow=function(self) self.EditBox:SetText(text or ""); self.EditBox:HighlightText(); self.EditBox:SetFocus() end,
        OnAccept=function(self) if onAccept then onAccept(self.EditBox:GetText()) end end,
        EditBoxOnEnterPressed=function(self) local p=self:GetParent(); if onAccept then onAccept(self:GetText()) end p:Hide() end}
    StaticPopup_Show("HCAA_EDIT")
end

-- Modern v1.5 interface.
-- Obsidian Ember: a restrained, modern dark skin with warm amber emphasis.
local GOLD_R,GOLD_G,GOLD_B=1,.68,.16
local EMBER_BG={.012,.015,.018,.98}
local EMBER_PANEL={.018,.024,.027,.97}
local EMBER_BORDER={.48,.32,.09,1}
local EMBER_BORDER_SOFT={.25,.20,.13,1}
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
    p:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",tile=true,tileSize=16,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    p:SetBackdropColor(unpack(EMBER_PANEL)); p:SetBackdropBorderColor(unpack(EMBER_BORDER_SOFT))
    if title then HLabel(p,title,12,-9,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B) end
    return p
end
local function HButton(parent,text,w,h)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize(w or 120,h or 25)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    b:SetBackdropColor(.025,.029,.031,1); b:SetBackdropBorderColor(unpack(EMBER_BORDER_SOFT))
    local label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); label:SetPoint("CENTER",0,0); label:SetTextColor(.94,.84,.61); b.label=label
    function b:SetText(value) self.label:SetText(value or "") end
    function b:GetText() return self.label:GetText() end
    b:SetText(text)
    b:HookScript("OnEnter",function(self) if self:IsEnabled() then self:SetBackdropColor(.105,.065,.018,1); self:SetBackdropBorderColor(unpack(EMBER_BORDER)) end end)
    b:HookScript("OnLeave",function(self) self:SetBackdropColor(.025,.029,.031,1); self:SetBackdropBorderColor(unpack(EMBER_BORDER_SOFT)) end)
    return b
end
local function HCheck(parent,text,x,y,get,set,enabledWhen)
    local b=CreateFrame("CheckButton",nil,parent,"BackdropTemplate"); b:SetPoint("TOPLEFT",x,y); b:SetSize(20,20)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}}); b:SetBackdropColor(.012,.014,.016,1); b:SetBackdropBorderColor(unpack(EMBER_BORDER_SOFT))
    local mark=b:CreateTexture(nil,"ARTWORK"); mark:SetTexture("Interface\\Buttons\\WHITE8X8"); mark:SetSize(10,10); mark:SetPoint("CENTER",0,0); mark:SetVertexColor(1,.62,.08,1); b.mark=mark
    local label=HLabel(b,text,27,-3,"GameFontHighlight")
    local function refresh()
        b:SetChecked(not not get()); mark:SetShown(not not get())
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
    local track=s:CreateTexture(nil,"BACKGROUND"); track:SetTexture("Interface\\Buttons\\WHITE8X8"); track:SetHeight(4); track:SetPoint("LEFT",6,0); track:SetPoint("RIGHT",-6,0); track:SetVertexColor(.20,.14,.06,1)
    local thumb=s:CreateTexture(nil,"ARTWORK"); thumb:SetTexture("Interface\\Buttons\\WHITE8X8"); thumb:SetSize(10,14); thumb:SetVertexColor(1,.62,.08,1); s:SetThumbTexture(thumb)
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
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize(size,size); b:SetPoint("TOPLEFT",x,y); b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=2,right=2,top=2,bottom=2}})
    HRegisterRefresh(function() local c=get(); b:SetBackdropColor(c[1] or 1,c[2] or 1,c[3] or 1,c[4] or 1); b:SetBackdropBorderColor(unpack(EMBER_BORDER)) end)
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
    if MIDNIGHT_SHAPE_SET[shape] then p.colorEnabled=false end
    ApplyCached()
    RefreshConfig()
end
local function HBuildGeneral(owner,page)
    local panelGap=10
    -- Compact 820px layout: keep the mode and preview panels generous, while
    -- reserving the narrow third column for the size controls.
    local topW=280
    local topH=250

    local mode=HPanel(page,"1. Arrow Mode"); mode:SetPoint("TOPLEFT",0,0); mode:SetSize(topW,topH)
    local modeOptions=IsEllesmereUI() and {{"Hidden","hidden"},{"Custom","custom"}} or {{"Hidden","hidden"},{"Blizzard Original","original"},{"Custom","custom"}}
    HDropdown(mode,18,-42,135,modeOptions,function() return Profile().mode end,function(v) SetMode(v) end)
    HCheck(mode,"Enable HCAA",18,-96,function() return Profile().enabled end,function(v) Profile().enabled=v end)
    local help=HLabel(mode,"Hide Blizzard's arrow, keep the original,\nor use one of your custom designs.",18,-142,"GameFontHighlight",.78,.78,.78); help:SetSpacing(5); help:SetWidth(300); help:SetJustifyH("LEFT")

    local prev=HPanel(page,"2. Preview"); prev:SetPoint("TOPLEFT",topW+panelGap,0); prev:SetSize(topW,topH)
    local glow=prev:CreateTexture(nil,"ARTWORK",nil,1); glow:SetBlendMode("ADD"); local arrow=prev:CreateTexture(nil,"ARTWORK",nil,2)
    local left=HButton(prev,"<",32,32); left:SetPoint("LEFT",16,5); left:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().rotation=(Profile().rotation-15)%360; ApplyCached(); RefreshConfig() end)
    local right=HButton(prev,">",32,32); right:SetPoint("RIGHT",-16,5); right:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().rotation=(Profile().rotation+15)%360; ApplyCached(); RefreshConfig() end)
    local info=prev:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); info:SetPoint("BOTTOM",0,36); info:SetWidth(235); info:SetJustifyH("CENTER")
    local reset=HButton(prev,"Reset Size / Rotation",168,24); reset:SetPoint("BOTTOM",0,7); reset:SetScript("OnClick",function() if Profile().mode~="custom" then return end; Profile().scale=1; Profile().rotation=0; Profile().offsetX=0; Profile().offsetY=0; ApplyCached(); RefreshConfig() end)
    HRegisterRefresh(function()
        local p=Profile(); local useColor=p.colorEnabled~=false; local c=useColor and (p.color or {1,1,1,1}) or {1,1,1,1}; local gc=p.glowColor or {1,.78,.05,1}; local custom=p.mode=="custom"; local shown=p.mode~="hidden"
        local sizeValue=custom and Clamp(82*(p.scale or 1),54,116) or 82
        arrow:ClearAllPoints(); arrow:SetPoint("CENTER",p.offsetX or 0,12+(p.offsetY or 0)); arrow:SetSize(sizeValue,sizeValue)
        if p.mode=="original" and arrow.SetAtlas then arrow:SetAtlas("UI-HUD-RotationHelper-Active-2x",true) else arrow:SetTexture(ShapePath(p.shape)) end
        if custom and arrow.SetDesaturated then arrow:SetDesaturated(useColor) elseif arrow.SetDesaturated then arrow:SetDesaturated(false) end
        arrow:SetVertexColor(c[1],c[2],c[3],c[4]); arrow:SetRotation(custom and math.rad(p.rotation or 0) or 0); arrow:SetAlpha(shown and math.max(.35,p.opacity or 0) or 0)
        glow:ClearAllPoints(); glow:SetPoint("CENTER",arrow,"CENTER",0,0); glow:SetSize(sizeValue+16,sizeValue+16); glow:SetTexture(ShapePath(p.shape)); if glow.SetDesaturated then glow:SetDesaturated(true) end; glow:SetVertexColor(gc[1],gc[2],gc[3],gc[4]); glow:SetRotation(custom and math.rad(p.rotation or 0) or 0); glow:SetAlpha(custom and p.glow and (p.glowIntensity or .65) or 0)
        left:SetEnabled(custom); right:SetEnabled(custom); reset:SetEnabled(custom); left:SetAlpha(custom and 1 or .35); right:SetAlpha(custom and 1 or .35); reset:SetAlpha(custom and 1 or .35)
        info:SetText(custom and string.format("Scale %.2f   Rot %d   X %d   Y %d",p.scale or 1,p.rotation or 0,p.offsetX or 0,p.offsetY or 0) or (p.mode=="original" and "Blizzard original preview" or "Arrow hidden"))
    end)

    local size=HPanel(page,"3. Size, Opacity & Position"); size:SetPoint("TOPLEFT",(topW+panelGap)*2,0); size:SetSize(200,topH)
    for _,region in ipairs({size:GetRegions()}) do
        if region and region.GetObjectType and region:GetObjectType()=="FontString" then
            region:SetFontObject("GameFontNormal")
            break
        end
    end
    local customEnabled=function() return Profile().mode=="custom" end
    local function CleanSlider(slider)
        local name=slider and slider:GetName()
        if not name then return slider end
        local low,high=_G[name.."Low"],_G[name.."High"]
        if low then low:Hide() end
        if high then high:Hide() end
        return slider
    end
    CleanSlider(HSlider(size,"Opacity",14,-32,172,0,100,1,function() return (Profile().opacity or 0)*100 end,function(v) Profile().opacity=v/100 end,function(v) return math.floor(v+.5).."%" end))
    CleanSlider(HSlider(size,"Arrow Scale",14,-70,172,.5,2,.05,function() return Profile().scale or 1 end,function(v) Profile().scale=v end,nil,customEnabled))
    CleanSlider(HSlider(size,"Arrow Rotation",14,-108,172,0,360,5,function() return Profile().rotation or 0 end,function(v) Profile().rotation=v end,function(v) return math.floor(v+.5).." deg" end,customEnabled))
    CleanSlider(HSlider(size,"Frame X",14,-146,172,-80,80,1,function() return Profile().offsetX or 0 end,function(v) Profile().offsetX=v end,function(v) return math.floor(v+.5) end,customEnabled))
    CleanSlider(HSlider(size,"Frame Y",14,-192,172,-80,80,1,function() return Profile().offsetY or 0 end,function(v) Profile().offsetY=v end,function(v) return math.floor(v+.5) end,customEnabled))

    local bottomY=-260
    local bottomH=330
    local shapesW=500
    local shapes=HPanel(page,"4. Shapes"); shapes:SetPoint("TOPLEFT",0,bottomY); shapes:SetSize(shapesW,bottomH)
    local color=HPanel(page,"5. Color & Glow"); color:SetPoint("TOPLEFT",shapesW+panelGap,bottomY); color:SetSize(270,bottomH)

    local tabClassic=HButton(shapes,"Classic Shapes",185,25); tabClassic:SetPoint("TOPLEFT",16,-34)
    local tabMidnight=HButton(shapes,"Midnight Shapes",185,25); tabMidnight:SetPoint("LEFT",tabClassic,"RIGHT",10,0)
    local classicPage=CreateFrame("Frame",nil,shapes); classicPage:SetPoint("TOPLEFT",10,-66); classicPage:SetSize(480,244)
    local midnightPage=CreateFrame("Frame",nil,shapes); midnightPage:SetAllPoints(classicPage)
    local activeShapeTab="classic"
    local function ShowShapeTab(which)
        activeShapeTab=which
        classicPage:SetShown(which=="classic"); midnightPage:SetShown(which=="midnight")
        local function mark(button,active) button:SetAlpha(active and 1 or .68) end
        mark(tabClassic,which=="classic"); mark(tabMidnight,which=="midnight")
    end
    tabClassic:SetScript("OnClick",function() ShowShapeTab("classic") end)
    tabMidnight:SetScript("OnClick",function() ShowShapeTab("midnight") end)

    local function BuildShapeGrid(panel,shapeList)
        for index,shape in ipairs(shapeList) do
            local shapeKey=shape; local col=(index-1)%5; local row=math.floor((index-1)/5)
            local b=CreateFrame("Button",nil,panel,"BackdropTemplate"); b:SetSize(54,54); b:SetPoint("TOPLEFT",18+col*90,-2-row*60)
            b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10}); b:SetBackdropColor(.025,.035,.035,1)
            local tex=b:CreateTexture(nil,"ARTWORK"); tex:SetSize(42,42); tex:SetPoint("CENTER",0,2); tex:SetTexture(ShapePath(shapeKey)); if MIDNIGHT_SHAPE_SET[shapeKey] then tex:SetVertexColor(1,1,1,1) else tex:SetVertexColor(1,.77,.08,1) end
            local num=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); num:SetPoint("BOTTOM",0,1); num:SetText(index)
            b:SetScript("OnClick",function() HSelectShape(shapeKey) end)
            b:SetScript("OnEnter",function(self) if Profile().mode~="custom" then return end; GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(SHAPE_LABELS[shapeKey],1,.82,0); GameTooltip:Show() end)
            b:SetScript("OnLeave",function() GameTooltip:Hide() end)
            HRegisterRefresh(function()
                local enabled=Profile().mode=="custom"; b:SetEnabled(enabled); b:SetAlpha(enabled and 1 or .32)
                if enabled and Profile().shape==shapeKey then b:SetBackdropBorderColor(1,.72,.05,1); b:SetBackdropColor(.13,.09,.01,1) else b:SetBackdropBorderColor(.30,.30,.26,1); b:SetBackdropColor(.025,.035,.035,1) end
            end)
        end
    end
    BuildShapeGrid(classicPage,CLASSIC_SHAPES)
    BuildShapeGrid(midnightPage,MIDNIGHT_SHAPES)
    ShowShapeTab("classic")

    local customMode=function() return Profile().mode=="custom" end
    local colorMode=function() local m=Profile().mode; return m=="custom" or m=="original" end
    HCheck(color,"Use Custom Arrow Color",18,-42,function() return Profile().colorEnabled~=false end,function(v) Profile().colorEnabled=v end,colorMode)
    local arrowColorEnabled=function() return colorMode() and Profile().colorEnabled~=false end
    local choose=HButton(color,"Choose Arrow Color",160,28); choose:SetPoint("TOPLEFT",18,-78); choose:SetScript("OnClick",function() if arrowColorEnabled() then OpenHCAAColorPicker("arrow") end end)
    local sw=HSwatch(color,202,-78,32,function() return Profile().color or {1,1,1,1} end); sw:SetScript("OnClick",function() if arrowColorEnabled() then OpenHCAAColorPicker("arrow") end end)
    local glowEnabled=function() return customMode() end
    HCheck(color,"Enable Glow",18,-132,function() return Profile().glow end,function(v) Profile().glow=v end,glowEnabled)
    local gb=HButton(color,"Choose Glow Color",160,28); gb:SetPoint("TOPLEFT",18,-168); gb:SetScript("OnClick",function() if glowEnabled() then OpenHCAAColorPicker("glow") end end)
    local gs=HSwatch(color,202,-168,32,function() return Profile().glowColor or {1,.78,.05,1} end); gs:SetScript("OnClick",function() if glowEnabled() then OpenHCAAColorPicker("glow") end end)
    HSlider(color,"Glow Intensity",18,-220,230,0,100,1,function() return (Profile().glowIntensity or .65)*100 end,function(v) Profile().glowIntensity=v/100 end,function(v) return math.floor(v+.5).."%" end,glowEnabled)
    local note=HLabel(color,"Color works with Blizzard Original and Custom.\nGlow is available in Custom mode only.",18,-268,"GameFontHighlightSmall",.72,.72,.72); local nf,ns,nflags=note:GetFont(); if nf then note:SetFont(nf,8,nflags) end; note:SetSpacing(2); note:SetWidth(230); note:SetJustifyH("LEFT")
    HRegisterRefresh(function()
        local ce=arrowColorEnabled(); choose:SetEnabled(ce); choose:SetAlpha(ce and 1 or .45); sw:SetEnabled(ce); sw:SetAlpha(ce and 1 or .45)
        local enabled=glowEnabled(); gb:SetEnabled(enabled); gb:SetAlpha(enabled and 1 or .45); gs:SetEnabled(enabled); gs:SetAlpha(enabled and 1 or .45)
    end)
end

local function HBuildRules(owner,page)
    local scope=HPanel(page,"Profile Scope"); scope:SetPoint("TOPLEFT",0,0); scope:SetSize(780,116)
    local scopeLabel=HLabel(scope,"Store settings:",0,-35,"GameFontHighlight"); scopeLabel:ClearAllPoints(); scopeLabel:SetPoint("TOP",0,-35); scopeLabel:SetWidth(740); scopeLabel:SetJustifyH("CENTER")
    local scopeDropdown=HDropdown(scope,0,-50,190,{{"Account-wide","account"},{"Per Character","character"},{"Per Specialization","spec"}},function() return HCAA_DB.profileMode or "account" end,function(v) HCAA_DB.profileMode=v end)
    scopeDropdown:ClearAllPoints(); scopeDropdown:SetPoint("TOP",scope,"TOP",0,-50)
    local active=HLabel(scope,"",0,-91,"GameFontNormal",GOLD_R,GOLD_G,GOLD_B); active:ClearAllPoints(); active:SetPoint("TOP",0,-91); active:SetWidth(740); active:SetJustifyH("CENTER")
    HRegisterRefresh(function() local map={account="Account-wide",character=CharacterKey(),spec=SpecKey()}; active:SetText("Active: "..(map[HCAA_DB.profileMode] or "Account-wide")) end)

    local combat=HPanel(page,"Combat Rule"); combat:SetPoint("TOPLEFT",0,-126); combat:SetSize(780,116)
    local combatLabel=HLabel(combat,"Assistant arrow visibility during combat:",0,-35,"GameFontHighlight"); combatLabel:ClearAllPoints(); combatLabel:SetPoint("TOP",0,-35); combatLabel:SetWidth(740); combatLabel:SetJustifyH("CENTER")
    local combatDropdown=HDropdown(combat,0,-57,190,{{"No combat rule","none"},{"Hide while in combat","hide_in_combat"},{"Show only in combat","show_in_combat"}},function() return Profile().autoCombat end,function(v) Profile().autoCombat=v end)
    combatDropdown:ClearAllPoints(); combatDropdown:SetPoint("TOP",combat,"TOP",0,-57)

    local zones=HPanel(page,"Allowed Zones"); zones:SetPoint("TOPLEFT",0,-252); zones:SetSize(780,178)
    local zoneList={{"Solo / Open World","solo"},{"Dungeon","dungeon"},{"Raid","raid"},{"Arena","arena"},{"Battleground","battleground"}}
    local positions={{185,-42},{425,-42},{185,-84},{425,-84},{305,-126}}
    for i,z in ipairs(zoneList) do local zoneLabel,zoneKey=z[1],z[2]; local pos=positions[i]; HCheck(zones,zoneLabel,pos[1],pos[2],function() return Profile().zones[zoneKey]~=false end,function(v) Profile().zones[zoneKey]=v end) end

    local note=HPanel(page,"How Rules Work"); note:SetPoint("TOPLEFT",0,-440); note:SetSize(780,75)
    local t=HLabel(note,"The selected scope controls where settings are stored. Zone and combat rules are reevaluated automatically.",0,-39,"GameFontHighlightSmall",.75,.75,.75); t:ClearAllPoints(); t:SetPoint("TOP",0,-39); t:SetWidth(740); t:SetJustifyH("CENTER")
end
local function HBuildKeybinds(owner,page)
    local box=HPanel(page,"Toggle Keybind"); box:SetPoint("TOPLEFT",0,0); box:SetSize(780,215)
    local guide=HLabel(box,"Click the button, then press the key combination you want.",0,-48,"GameFontHighlight"); guide:SetPoint("TOP",0,-48); guide:SetWidth(710); guide:SetJustifyH("CENTER")
    local current=HLabel(box,"",0,-92,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B); current:ClearAllPoints(); current:SetPoint("TOP",0,-88); current:SetWidth(710); current:SetJustifyH("CENTER")
    local capture=HButton(box,"Set Toggle Key",190,32); capture:SetPoint("TOP",-103,-128)
    local clear=HButton(box,"Clear Binding",150,32); clear:SetPoint("LEFT",capture,"RIGHT",16,0)
    local function refreshKey() local k1,k2=GetBindingKey("HCAA_TOGGLE"); current:SetText("Current: "..(k1 or k2 or "Not Bound")) end; HRegisterRefresh(refreshKey)
    capture:SetScript("OnClick",function(self) self:SetText("Press a key..."); self:EnableKeyboard(true); if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end end)
    capture:SetScript("OnKeyDown",function(self,key)
        if key=="ESCAPE" then self:EnableKeyboard(false); self:SetText("Set Toggle Key"); return end
        if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
        local combo=(IsControlKeyDown() and "CTRL-" or "")..(IsAltKeyDown() and "ALT-" or "")..(IsShiftKeyDown() and "SHIFT-" or "")..key
        SetBinding(combo,"HCAA_TOGGLE"); SaveBindings(GetCurrentBindingSet()); self:EnableKeyboard(false); self:SetText("Set Toggle Key"); refreshKey(); Print("Keybind set to "..combo..".")
    end)
    clear:SetScript("OnClick",function() local k1,k2=GetBindingKey("HCAA_TOGGLE"); if k1 then SetBinding(k1) end; if k2 then SetBinding(k2) end; SaveBindings(GetCurrentBindingSet()); refreshKey() end)
    local help=HPanel(page,"Slash Commands"); help:SetPoint("TOPLEFT",0,-225); help:SetSize(780,290)
    local commands="/hcaa - Open options\n/hcaa on | off | toggle\n/hcaa opacity 0-100\n/hcaa mode hidden | original | custom (original: Blizzard UI only)\n/hcaa shape NAME\n/hcaa reset"
    local cmd=HLabel(help,commands,0,-48,"GameFontHighlight"); cmd:ClearAllPoints(); cmd:SetPoint("TOP",0,-48); cmd:SetWidth(710); cmd:SetJustifyH("CENTER"); cmd:SetSpacing(8)
end

local function HBuildStats(owner,page)
    local box=HPanel(page,"Statistics"); box:SetPoint("TOPLEFT",0,0); box:SetSize(780,245)
    local eventsText=HLabel(box,"",0,-65,"GameFontNormalHuge",GOLD_R,GOLD_G,GOLD_B); eventsText:ClearAllPoints(); eventsText:SetPoint("TOP",0,-64); eventsText:SetWidth(710); eventsText:SetJustifyH("CENTER")
    local timeText=HLabel(box,"",0,-135,"GameFontNormalLarge",.25,1,.55); timeText:ClearAllPoints(); timeText:SetPoint("TOP",0,-132); timeText:SetWidth(710); timeText:SetJustifyH("CENTER")
    HRegisterRefresh(function() local s=HCAA_DB.statistics or {}; eventsText:SetText(string.format("Hidden Events: %d",s.hiddenCount or 0)); local sec=s.hiddenSeconds or 0; timeText:SetText(string.format("Hidden Time: %dh %dm %ds",math.floor(sec/3600),math.floor((sec%3600)/60),sec%60)) end)
    local clear=HButton(box,"Clear Statistics",160,28); clear:SetPoint("BOTTOM",0,22); clear:SetScript("OnClick",function() HCAA_DB.statistics={hiddenCount=0,hiddenSeconds=0,lastStart=nil}; RefreshConfig(); Print("Statistics cleared.") end)
    local status=HPanel(page,"Current Status"); status:SetPoint("TOPLEFT",0,-255); status:SetSize(780,260)
    local textLabel=HLabel(status,"",0,-50,"GameFontHighlight"); textLabel:ClearAllPoints(); textLabel:SetPoint("TOP",0,-50); textLabel:SetWidth(710); textLabel:SetJustifyH("CENTER"); textLabel:SetSpacing(8)
    HRegisterRefresh(function() local p=Profile(); local err=runtimeStatus.lastError and ("\nLast Error: "..runtimeStatus.lastError) or ""; textLabel:SetText(string.format("Enabled: %s\nMode: %s\nShape: %s\nOpacity: %d%%\nTargets: %d (Blizzard %d / EllesmereUI %d / ElvUI %d)\nZone: %s\nDetected UI: %s%s",p.enabled and "Yes" or "No",p.mode,SHAPE_LABELS[p.shape] or p.shape,math.floor((p.opacity or 0)*100+.5),runtimeStatus.count or 0,runtimeStatus.blizzard or 0,runtimeStatus.ellesmere or 0,runtimeStatus.elvui or 0,ZoneType(),DetectedUI(),err)) end)
end

local function HBuildAbout(owner,page)
    local box=HPanel(page,"About HCAA"); box:SetPoint("TOPLEFT",0,0); box:SetSize(780,500)
    local icon=box:CreateTexture(nil,"ARTWORK"); icon:SetSize(82,82); icon:SetPoint("TOP",0,-28); icon:SetTexture("Interface\\AddOns\\HCAA\\icon")
    local title=HLabel(box,"Hide And Customize Assistant Arrow",0,-136,"GameFontNormalHuge",GOLD_R,GOLD_G,GOLD_B); title:ClearAllPoints(); title:SetPoint("TOP",0,-116); title:SetWidth(740); title:SetJustifyH("CENTER")
    local ver=HLabel(box,"Version "..VERSION,0,-172,"GameFontHighlight",.25,1,.55); ver:ClearAllPoints(); ver:SetPoint("TOP",0,-150); ver:SetWidth(740); ver:SetJustifyH("CENTER")
    local author=HLabel(box,"Author: FaneyQ8",0,-198,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B); author:ClearAllPoints(); author:SetPoint("TOP",0,-176); author:SetWidth(740); author:SetJustifyH("CENTER")
    local desc=HLabel(box,"Customize Blizzard's Single-Button Assistant Arrow with custom frames, colors, glow and automatic rules.",0,-236,"GameFontHighlight"); desc:ClearAllPoints(); desc:SetPoint("TOP",0,-210); desc:SetWidth(710); desc:SetJustifyH("CENTER")

    local community=HLabel(box,"Community Links",0,-286,"GameFontNormalLarge",GOLD_R,GOLD_G,GOLD_B); community:ClearAllPoints(); community:SetPoint("TOP",0,-252); community:SetWidth(710); community:SetJustifyH("CENTER")
    local function SocialIcon(key,x)
        local data=SOCIAL[key]
        local b=CreateFrame("Button",nil,box,"BackdropTemplate")
        b:SetSize(50,50); b:SetPoint("TOPLEFT",x,-282)
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
    local order={"twitch","tiktok","discord","battlenet","github"}
    local startX=(790-(5*50+4*44))/2
    for i,key in ipairs(order) do SocialIcon(key,startX+(i-1)*94) end
    local hint=HLabel(box,"Click an icon to copy its link or account name.",0,-388,"GameFontHighlightSmall",.75,.75,.75); hint:ClearAllPoints(); hint:SetPoint("TOP",0,-348); hint:SetWidth(710); hint:SetJustifyH("CENTER")

    local status=HPanel(box,"Current Build"); status:SetPoint("TOP",0,-382); status:SetSize(710,108)
    local st=HLabel(status,"",0,-38,"GameFontHighlight"); st:ClearAllPoints(); st:SetPoint("TOP",0,-38); st:SetSpacing(7); st:SetWidth(670); st:SetJustifyH("CENTER")
    HRegisterRefresh(function()
        local p=Profile()
        st:SetText(string.format("Mode: %s    Shape: %s    Opacity: %d%%\nDetected UI: %s\nActive Assistant Buttons: %d",
            p.mode,SHAPE_LABELS[p.shape] or p.shape,math.floor((p.opacity or 0)*100+.5),DetectedUI(),(runtimeStatus.ellesmere or 0)+(runtimeStatus.elvui or 0)+(runtimeStatus.blizzard or 0)))
    end)
end

local function CreateModernConfig()
    local f=CreateFrame("Frame","HCAAConfigFrameModern",UIParent,"BasicFrameTemplateWithInset"); f:SetSize(820,760); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide(); f.refreshers={}; hBuildingConfig=f
    -- BasicFrameTemplateWithInset uses named texture regions rather than a
    -- BackdropTemplate, so tint its existing layers instead of calling SetBackdrop.
    if f.Bg then f.Bg:SetVertexColor(unpack(EMBER_BG)) end
    if f.InsetBg then f.InsetBg:SetVertexColor(.008,.011,.013,.96) end
    if f.TitleBg then f.TitleBg:SetVertexColor(.04,.028,.010,1) end
    for _,region in ipairs({f.TopBorder,f.BottomBorder,f.LeftBorder,f.RightBorder,f.TopLeftCorner,f.TopRightCorner,f.BotLeftCorner,f.BotRightCorner,f.InsetBorderTop,f.InsetBorderBottom,f.InsetBorderLeft,f.InsetBorderRight,f.InsetBorderTopLeft,f.InsetBorderTopRight,f.InsetBorderBottomLeft,f.InsetBorderBottomRight}) do if region then region:SetVertexColor(unpack(EMBER_BORDER_SOFT)) end end
    f.TitleText:SetText("HCAA v"..VERSION.." - Hide And Customize Assistant Arrow"); f.TitleText:SetTextColor(GOLD_R,GOLD_G,GOLD_B)
    local nav=HPanel(f); nav:SetPoint("TOPLEFT",12,-42); nav:SetSize(796,58)
    local tabs={{"General","Interface\\Icons\\INV_Misc_Gear_01",HBuildGeneral},{"Auto Rules","Interface\\Icons\\Ability_DualWield",HBuildRules},{"Keybinds","Interface\\Icons\\INV_Misc_Key_04",HBuildKeybinds},{"Stats","Interface\\Icons\\INV_Misc_Note_06",HBuildStats},{"About","Interface\\AddOns\\HCAA\\icon",HBuildAbout}}
    f.pages={}; f.tabButtons={}
    function f:ShowTab(index)
        self.activeTab=index
        for i,p in ipairs(self.pages) do
            p:SetShown(i==index)
            local b=self.tabButtons[i]
            if i==index then b:SetBackdropColor(.13,.075,.018,1); b:SetBackdropBorderColor(unpack(EMBER_BORDER)); b.label:SetTextColor(1,.79,.30)
            else b:SetBackdropColor(.018,.022,.024,.98); b:SetBackdropBorderColor(unpack(EMBER_BORDER_SOFT)); b.label:SetTextColor(.78,.75,.68) end
        end
        RefreshConfig()
    end
    for i,tab in ipairs(tabs) do
        local tabIndex=i; local b=CreateFrame("Button",nil,nav,"BackdropTemplate"); b:SetSize(150,42); b:SetPoint("TOPLEFT",10+(i-1)*157,-8)
        b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
        local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(24,24); icon:SetPoint("LEFT",12,0); icon:SetTexture(tab[2]); if tab[1]=="About" then icon:SetTexCoord(0,1,0,1) else icon:SetTexCoord(.08,.92,.08,.92) end
        local label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); label:SetPoint("LEFT",icon,"RIGHT",8,0); label:SetText(tab[1]); b.label=label
        b:SetScript("OnClick",function() f:ShowTab(tabIndex) end); f.tabButtons[i]=b
        local page=CreateFrame("Frame",nil,f); page:SetPoint("TOPLEFT",20,-110); page:SetSize(780,600); page:Hide(); f.pages[i]=page; tab[3](f,page)
    end
    local reset=HButton(f,"Reset Current Scope",160,28); reset:SetPoint("BOTTOMLEFT",20,12); reset:SetScript("OnClick",function() local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); RefreshConfig() end)
    local cancel=HButton(f,"Cancel",120,28); cancel:SetPoint("BOTTOMRIGHT",-152,12); local okay=HButton(f,"Okay",120,28); okay:SetPoint("BOTTOMRIGHT",-20,12)
    function f:CancelChanges() if self.snapshot then wipe(HCAA_DB); for k,v in pairs(DeepCopy(self.snapshot)) do HCAA_DB[k]=v end end; ApplyCached(); self:Hide() end
    cancel:SetScript("OnClick",function() f:CancelChanges() end); f.CloseButton:SetScript("OnClick",function() f:CancelChanges() end); okay:SetScript("OnClick",function() f.snapshot=DeepCopy(HCAA_DB); f:Hide() end)
    hBuildingConfig=nil; configFrame=f; f:ShowTab(1)
end

RefreshConfig=function() if configFrame and configFrame:IsShown() then for _,fn in ipairs(configFrame.refreshers or {}) do fn() end end end
OpenConfig=function() if not configFrame or not configFrame.refreshers then CreateModernConfig() end; if configFrame:IsShown() then configFrame:CancelChanges() else configFrame.snapshot=DeepCopy(HCAA_DB); configFrame:Show(); RefreshConfig() end end

local settingsCategory
local function RegisterSettingsCategory()
    if settingsCategory then return end
    local panel=CreateFrame("Frame","HCAASettingsPanel")
    panel.name="HCAA"
    local title=panel:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",16,-16)
    title:SetText("Hide And Customize Assistant Arrow (HCAA)")
    local description=panel:CreateFontString(nil,"ARTWORK","GameFontHighlight")
    description:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-12)
    description:SetWidth(560)
    description:SetJustifyH("LEFT")
    description:SetText("Open the HCAA configuration window to customize the Assistant Arrow, shapes, colors, rules, keybinds, and other settings.")
    local openButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    openButton:SetSize(190,28)
    openButton:SetPoint("TOPLEFT",description,"BOTTOMLEFT",0,-18)
    openButton:SetText("Open HCAA Settings")
    openButton:SetScript("OnClick",function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        OpenConfig()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category=Settings.RegisterCanvasLayoutCategory(panel,"HCAA")
        Settings.RegisterAddOnCategory(category)
        settingsCategory=category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        settingsCategory=panel
    end
end

local function UpdateMinimapPosition()
    if not minimapButton or not Minimap then return end
    local a=math.rad(HCAA_DB.minimap.angle or 225)
    -- Keep the button seated on the minimap ring, with only a slight overlap.
    local radius=((Minimap:GetWidth() or 140)/2)+8
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*radius,math.sin(a)*radius)
end
local function CreateMinimap()
    if minimapButton or not Minimap then return end
    local b=CreateFrame("Button","HCAAMinimapButton",Minimap); b:SetSize(32,32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel((Minimap:GetFrameLevel() or 0)+8); b:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp"); b:EnableMouseWheel(true); b:RegisterForDrag("LeftButton")
    local i=b:CreateTexture(nil,"BACKGROUND"); i:SetTexture("Interface\\AddOns\\HCAA\\icon"); i:SetSize(22,22); i:SetPoint("CENTER"); b.icon=i
    local border=b:CreateTexture(nil,"OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54,54); border:SetPoint("TOPLEFT",b,"TOPLEFT",0,0)
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
    elseif low=="reset" then local p=Profile(); wipe(p); CopyDefaults(DEFAULT_PROFILE,p); ApplyCached(); Print("Profile reset.")
    else
        local o=low:match("^opacity%s+(%d+)$"); local m=low:match("^mode%s+(%a+)$"); local sh=low:match("^shape%s+([%w_]+)$")
        if o then SetOpacity(Clamp(o,0,100)/100) elseif m then SetMode(m) elseif sh and (VALID_SHAPES[sh] or LEGACY_SHAPE_MAP[sh]) then Profile().shape=NormalizeShape(sh); Profile().mode="custom"; ApplyCached() else Print("Commands: /hcaa on|off|toggle|opacity 0-100|mode hidden/original/custom|shape NAME|reset") end
    end
end

local function FirstRun()
    if not HCAA_DB.firstRun then return end HCAA_DB.firstRun=false
    StaticPopupDialogs.HCAA_WELCOME={text="Welcome to HCAA v"..VERSION.."!\n\nChoose a starting mode. You can customize 20 shapes, colors, rules and profile scope from the minimap button.",button1="Hide Arrow",button2="Customize",button3="Keep Original",timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function() SetMode("hidden") end, OnCancel=function() SetMode("custom"); OpenConfig() end, OnAlt=function() if IsEllesmereUI() then SetMode("custom"); OpenConfig() else SetMode("original") end end}
    StaticPopup_Show("HCAA_WELCOME")
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
    -- A regular combat click still fires OnMouseDown on EllesmereUI buttons.
    -- Treating it as a drag hid the custom overlay until the next rescan, which
    -- made the Assistant Arrow blink whenever combat started or an ability was used.
    if InCombatLockdown() then return end
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
    if InCombatLockdown() then return false end
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
            button:HookScript("OnReceiveDrag",function(self)
                if assistantMovePending and self~=assistantMoveSource and CompleteAssistantMove(self) then return end
                ScheduleActionBarRescanBurst()
            end)
            button:HookScript("OnMouseUp",function(self)
                -- Normal ability clicks also fire MouseUp. Only rescan if a
                -- real drag operation is in progress, otherwise the custom
                -- frame is briefly hidden after every cast.
                if assistantMovePending then
                    if self~=assistantMoveSource and CompleteAssistantMove(self) then return end
                    ScheduleActionBarRescanBurst()
                end
            end)
            -- Mouseover and target changes can make EllesmereUI show a child of
            -- the action button. A quiet scan is enough here; rebuilding every
            -- owner makes the custom frame visibly blink while hovering units.
            button:HookScript("OnShow",function() ScheduleScan(0.05) end)
            button:HookScript("OnAttributeChanged",function(self,name)
                if name=="action" or name=="type" then
                    if assistantMoveDestination==self then
                        activeEllesmereOwners[self]=true
                        C_Timer.After(0,function()
                            if HCAA_DB then pcall(ProcessEllesmereOwner,self) end
                        end)
                    else
                        ScheduleScan(0.05)
                    end
                end
            end)
        end
    end
end

function ScheduleActionBarRescanBurst()
    -- EllesmereUI changes secure action-button state as combat begins. Do not
    -- clear the owner table in combat: ResetEllesmereTracking hides the overlay
    -- briefly and is the source of the visible blink. A normal deferred scan
    -- refreshes alpha safely without tearing down the current visual.
    if InCombatLockdown() then
        HookEllesmereButtons()
        ScheduleScan(0.10)
        return
    end
    actionBarRescanGeneration=actionBarRescanGeneration+1
    local generation=actionBarRescanGeneration
    -- An automatic action-bar refresh must not tear down existing owners. UI
    -- mouseover state can emit the same events as a moved action and clearing
    -- this table caused the custom frame to disappear for a frame. Real moves
    -- are handled explicitly by BeginAssistantMove/CompleteAssistantMove.
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
    if event=="ADDON_LOADED" and arg==ADDON_NAME then HCAA_DB=MigrateDatabase(HCAA_DB); RegisterSettingsCategory(); return end
    if event=="ADDON_LOADED" and (arg=="ElvUI" or arg=="ElvUI_Libraries") then
        C_Timer.After(0.25,function() if HCAA_DB then InstallElvUIHooks(); ScanAll() end end)
    end
    if event=="PLAYER_LOGIN" then CreateMinimap(); FirstRun(); InstallElvUIHooks(); SchedulePostReloadReattach(); C_Timer.After(0.75,function() if HCAA_DB then InstallElvUIHooks(); ScanAll() end end) end
    if event=="PLAYER_ENTERING_WORLD" then SchedulePostReloadReattach() end
    if event=="PLAYER_REGEN_DISABLED" then
        -- Keep the current EllesmereUI owner intact while entering combat.
        ScheduleScan(0.10)
    elseif event=="PLAYER_REGEN_ENABLED" then
        -- Once combat ends, action buttons are safe to settle and reattach.
        C_Timer.After(0.12,function() if HCAA_DB then ScheduleActionBarRescanBurst() end end)
    elseif event=="ACTIONBAR_SLOT_CHANGED" or event=="ACTIONBAR_PAGE_CHANGED" or event=="ACTIONBAR_SHOWGRID" or event=="ACTIONBAR_HIDEGRID" or event=="CURSOR_CHANGED" then
        ScheduleActionBarRescanBurst()
    else
        ScheduleScan(event=="PLAYER_LOGIN" and .20 or .05)
    end
end)
hiddenTicker=C_Timer.NewTicker(5,function() local s=HCAA_DB and HCAA_DB.statistics; if s and s.lastStart then s.hiddenSeconds=(s.hiddenSeconds or 0)+5; s.lastStart=time() end end)
