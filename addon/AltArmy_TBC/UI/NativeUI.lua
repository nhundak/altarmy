-- AltArmy TBC — Native Blizzard UI capability detection.
-- Forever reskins stock templates/atlases in place; TBC Anniversary lacks a few retail-only
-- pieces (e.g. LargeSideTabButtonTemplate). UI code asks here before choosing a template or
-- its fallback. See docs/WOW_FOREVER_NATIVE_UI_RESEARCH.md.
-- Loaded before Theme.lua in the .toc; must bootstrap the namespace here.

AltArmy = AltArmy or {}
AltArmy.NativeUI = AltArmy.NativeUI or {}

local NativeUI = AltArmy.NativeUI

--- True when a virtual XML template named `name` exists on this client.
--- `frameType` is only used by the CreateFrame fallback (default "Frame").
function NativeUI.HasTemplate(name, frameType)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local xml = _G.C_XMLUtil
    if xml and xml.GetTemplateInfo then
        local ok, info = pcall(xml.GetTemplateInfo, name)
        return (ok and info ~= nil) and true or false
    end
    if not _G.CreateFrame then
        return false
    end
    local ok, frame = pcall(_G.CreateFrame, frameType or "Frame", nil, nil, name)
    if ok and frame and frame.Hide then
        frame:Hide()
    end
    return (ok and frame ~= nil) and true or false
end

--- True when the texture atlas `name` exists on this client.
function NativeUI.HasAtlas(name)
    local tex = _G.C_Texture
    if type(name) ~= "string" or not tex or not tex.GetAtlasInfo then
        return false
    end
    local ok, info = pcall(tex.GetAtlasInfo, name)
    return (ok and info ~= nil) and true or false
end

local function hasField(tbl, key)
    return type(tbl) == "table" and tbl[key] ~= nil
end

-- Layouts Theme.ApplyBackdrop draws natively; present on both Forever and TBC Anniversary.
NativeUI.NINE_SLICE_LAYOUTS = { "InsetFrameTemplate", "Dialog", "TooltipDefaultLayout" }

local function hasNineSliceLayouts()
    local util = _G.NineSliceUtil
    if not hasField(util, "ApplyLayoutByName") or not hasField(util, "GetLayout") then
        return false
    end
    for _, name in ipairs(NativeUI.NINE_SLICE_LAYOUTS) do
        if not util.GetLayout(name) then
            return false
        end
    end
    return true
end

--- Probe the client once for every native widget the reskin relies on.
function NativeUI.DetectCaps()
    local has = NativeUI.HasTemplate
    return {
        portraitFrame = has("PortraitFrameTemplate"),
        sideTabs = has("LargeSideTabButtonTemplate") and NativeUI.HasAtlas("common-sidetab"),
        minimalScrollBar = has("MinimalScrollBar", "EventFrame")
            and hasField(_G.ScrollUtil, "InitScrollFrameWithScrollBar"),
        wowStyleDropdown = has("WowStyle1DropdownTemplate", "DropdownButton")
            and _G.MenuUtil ~= nil,
        searchBox = has("SearchBoxTemplate", "EditBox"),
        inputBox = has("InputBoxTemplate", "EditBox"),
        checkButton = has("UICheckButtonTemplate", "CheckButton"),
        insetFrame = has("InsetFrameTemplate"),
        panelButton = has("UIPanelButtonTemplate", "Button"),
        tooltipBackdrop = has("TooltipBackdropTemplate"),
        nineSlice = hasNineSliceLayouts(),
    }
end

local cachedCaps = nil

--- Cached DetectCaps(); templates never change within a session.
function NativeUI.GetCaps()
    if not cachedCaps then
        cachedCaps = NativeUI.DetectCaps()
    end
    return cachedCaps
end

function NativeUI.ResetCaps()
    cachedCaps = nil
end

local function atlasSize(name)
    local tex = _G.C_Texture
    if not tex or not tex.GetAtlasInfo then return nil end
    local ok, info = pcall(tex.GetAtlasInfo, name)
    if not ok or not info then return nil end
    return { width = info.width, height = info.height }
end

local function frameSize(frame)
    if not frame or not frame.GetSize then return nil end
    local w, h = frame:GetSize()
    return { width = w, height = h, scale = frame.GetScale and frame:GetScale() or nil }
end

--- Capability + native-geometry snapshot for the dev-dump tool (no-op unless debug is on).
--- Used to confirm which fallbacks each client (Forever vs TBC Anniversary) takes.
function NativeUI.DumpCaps()
    local Debug = AltArmy.Debug
    if not Debug or not Debug.Dump then return end
    local version, build, _, interface = nil, nil, nil, nil
    if _G.GetBuildInfo then
        version, build, _, interface = _G.GetBuildInfo()
    end
    Debug.Dump("nativeui-caps", {
        client = { version = version, build = build, interface = interface, project = _G.WOW_PROJECT_ID },
        caps = NativeUI.DetectCaps(),
        atlases = {
            sidetab = atlasSize("common-sidetab"),
            sidetabSelected = atlasSize("common-sidetab-selected"),
        },
        characterFrame = {
            constHeight = _G.CHARACTER_FRAME_HEIGHT,
            constWidth = _G.CHARACTER_FRAME_WIDTH,
            size = frameSize(_G.CharacterFrame),
        },
        uiParentScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or nil,
    })
end

if _G.CreateFrame then
    local loginFrame = _G.CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        NativeUI.DumpCaps()
    end)
end
