--[[
  Unit tests for NativeUI.lua (Blizzard template / atlas capability detection).
  Run from project root: npm test
]]

describe("NativeUI", function()
  local NativeUI
  local saved

  local GLOBALS = { "C_XMLUtil", "C_Texture", "CreateFrame", "ScrollUtil", "MenuUtil", "NineSliceUtil", "CreateFramePool" }

  local function stubClient(templates, atlases, extra)
    templates = templates or {}
    atlases = atlases or {}
    _G.C_XMLUtil = {
      GetTemplateInfo = function(name)
        if templates[name] then return { type = "Frame", width = 0, height = 0 } end
        return nil
      end,
    }
    _G.C_Texture = {
      GetAtlasInfo = function(name)
        return atlases[name]
      end,
    }
    extra = extra or {}
    _G.ScrollUtil = extra.ScrollUtil
    _G.MenuUtil = extra.MenuUtil
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
  end)

  before_each(function()
    saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    package.loaded["NativeUI"] = nil
    AltArmy.NativeUI = nil
    require("NativeUI")
    NativeUI = AltArmy.NativeUI
  end)

  after_each(function()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end)

  describe("HasTemplate", function()
    it("uses C_XMLUtil.GetTemplateInfo when available", function()
      stubClient({ PortraitFrameTemplate = true })
      assert.is_true(NativeUI.HasTemplate("PortraitFrameTemplate"))
      assert.is_false(NativeUI.HasTemplate("LargeSideTabButtonTemplate"))
    end)

    it("falls back to pcall(CreateFrame) without C_XMLUtil", function()
      _G.C_XMLUtil = nil
      _G.CreateFrame = function(_, _, _, template)
        if template ~= "InputBoxTemplate" then error("unknown template") end
        return { Hide = function() end }
      end
      assert.is_true(NativeUI.HasTemplate("InputBoxTemplate", "EditBox"))
      assert.is_false(NativeUI.HasTemplate("SearchBoxTemplate", "EditBox"))
    end)

    it("returns false for empty names and when GetTemplateInfo errors", function()
      _G.C_XMLUtil = { GetTemplateInfo = function() error("boom") end }
      assert.is_false(NativeUI.HasTemplate(""))
      assert.is_false(NativeUI.HasTemplate(nil))
      assert.is_false(NativeUI.HasTemplate("PortraitFrameTemplate"))
    end)
  end)

  describe("HasAtlas", function()
    it("is true only when C_Texture reports atlas info", function()
      stubClient({}, { ["common-sidetab"] = { width = 48, height = 53 } })
      assert.is_true(NativeUI.HasAtlas("common-sidetab"))
      assert.is_false(NativeUI.HasAtlas("common-sidetab-missing"))
    end)

    it("is false without C_Texture", function()
      _G.C_Texture = nil
      assert.is_false(NativeUI.HasAtlas("common-sidetab"))
    end)
  end)

  describe("DetectCaps", function()
    it("reports the Forever feature set", function()
      stubClient({
        PortraitFrameTemplate = true,
        LargeSideTabButtonTemplate = true,
        MinimalScrollBar = true,
        WowStyle1DropdownTemplate = true,
        WowStyle1FilterDropdownTemplate = true,
        SearchBoxTemplate = true,
        InputBoxTemplate = true,
        UICheckButtonTemplate = true,
        InsetFrameTemplate = true,
        UIPanelButtonTemplate = true,
        TooltipBackdropTemplate = true,
      }, { ["common-sidetab"] = { width = 48, height = 53 } }, {
        ScrollUtil = { InitScrollFrameWithScrollBar = function() end },
        MenuUtil = { CreateContextMenu = function() end },
      })
      local caps = NativeUI.DetectCaps()
      assert.is_true(caps.portraitFrame)
      assert.is_true(caps.sideTabs)
      assert.is_true(caps.minimalScrollBar)
      assert.is_true(caps.wowStyleDropdown)
      assert.is_true(caps.searchBox)
      assert.is_true(caps.inputBox)
      assert.is_true(caps.checkButton)
      assert.is_true(caps.insetFrame)
      assert.is_true(caps.panelButton)
      assert.is_true(caps.tooltipBackdrop)
    end)

    it("reports no side tabs on TBC (template missing)", function()
      stubClient({ PortraitFrameTemplate = true, MinimalScrollBar = true }, {}, {
        ScrollUtil = { InitScrollFrameWithScrollBar = function() end },
      })
      local caps = NativeUI.DetectCaps()
      assert.is_true(caps.portraitFrame)
      assert.is_false(caps.sideTabs)
      assert.is_true(caps.minimalScrollBar)
    end)

    it("requires the sidetab atlas as well as the template", function()
      stubClient({ LargeSideTabButtonTemplate = true }, {})
      assert.is_false(NativeUI.DetectCaps().sideTabs)
    end)

    it("requires ScrollUtil binding for minimal scroll bars", function()
      stubClient({ MinimalScrollBar = true })
      assert.is_false(NativeUI.DetectCaps().minimalScrollBar)
    end)

    it("reports nine-slice chrome only when NineSliceUtil has the shared layouts", function()
      stubClient({})
      _G.NineSliceUtil = nil
      assert.is_false(NativeUI.DetectCaps().nineSlice)
      local layouts = { InsetFrameTemplate = {}, Dialog = {}, TooltipDefaultLayout = {} }
      _G.NineSliceUtil = {
        ApplyLayoutByName = function() end,
        GetLayout = function(name) return layouts[name] end,
      }
      assert.is_true(NativeUI.DetectCaps().nineSlice)
      layouts.Dialog = nil
      assert.is_false(NativeUI.DetectCaps().nineSlice)
    end)

    it("reports top tabs, and icon tabs only with the Forever spellbook tab art", function()
      _G.CreateFramePool = function() end
      stubClient({ TabSystemTemplate = true, TabSystemTopButtonTemplate = true }, {})
      local caps = NativeUI.DetectCaps()
      assert.is_true(caps.topTabs)
      assert.is_false(caps.iconTabs)
      stubClient({ TabSystemTemplate = true, TabSystemTopButtonTemplate = true },
        { ["spellbook-Tab-Frame-C60"] = { width = 44, height = 40 } })
      assert.is_true(NativeUI.DetectCaps().iconTabs)
      stubClient({ TabSystemTemplate = true }, { ["spellbook-Tab-Frame-C60"] = {} })
      caps = NativeUI.DetectCaps()
      assert.is_false(caps.topTabs)
      assert.is_false(caps.iconTabs)
    end)

    it("reports classic panel top tabs when the template and PanelTemplates helpers exist", function()
      local savedSel, savedDesel = _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab
      _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab = function() end, function() end
      stubClient({ PanelTopTabButtonTemplate = true })
      local caps = NativeUI.DetectCaps()
      _G.PanelTemplates_SelectTab = nil
      local without = NativeUI.DetectCaps()
      _G.PanelTemplates_SelectTab, _G.PanelTemplates_DeselectTab = savedSel, savedDesel
      assert.is_true(caps.panelTopTabs)
      assert.is_false(caps.topTabs)
      assert.is_false(without.panelTopTabs)
    end)

    it("requires MenuUtil for WowStyle dropdowns", function()
      stubClient({ WowStyle1DropdownTemplate = true })
      assert.is_false(NativeUI.DetectCaps().wowStyleDropdown)
    end)
  end)

  describe("GetCaps", function()
    it("caches until ResetCaps", function()
      stubClient({ PortraitFrameTemplate = true })
      local first = NativeUI.GetCaps()
      assert.is_true(first.portraitFrame)
      stubClient({})
      assert.are.equal(first, NativeUI.GetCaps())
      NativeUI.ResetCaps()
      assert.is_false(NativeUI.GetCaps().portraitFrame)
    end)
  end)
end)
