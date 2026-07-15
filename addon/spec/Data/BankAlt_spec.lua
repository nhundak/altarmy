--[[ Unit tests for BankAlt.lua — run: npm test ]]

describe("BankAlt", function()
    local B

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CharKey")
        package.loaded["BankAlt"] = nil
        require("BankAlt")
        B = AltArmy.BankAlt
        assert.truthy(B)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        B.Ensure()
    end)

    it("Ensure initializes bankAlts table", function()
        B.Ensure()
        assert.is_table(AltArmyTBC_Options.bankAlts)
    end)

    it("Is returns false for unknown characters", function()
        assert.is_false(B.Is("Alice", "RealmA"))
    end)

    it("Set and Is round-trip", function()
        B.Set("Alice", "RealmA", true)
        assert.is_true(B.Is("Alice", "RealmA"))
        assert.is_false(B.Is("Bob", "RealmA"))
    end)

    it("Set false clears the flag", function()
        B.Set("Alice", "RealmA", true)
        B.Set("Alice", "RealmA", false)
        assert.is_false(B.Is("Alice", "RealmA"))
        assert.is_nil(AltArmyTBC_Options.bankAlts["RealmA\\Alice"])
    end)

    it("IconMarkup returns a texture escape", function()
        local markup = B.IconMarkup()
        assert.matches("|T.-|t", markup)
    end)

    describe("GetTooltipText", function()
        setup(function()
            _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
                MAGE = { r = 0.41, g = 0.8, b = 0.94 },
            }
            package.loaded["ClassColor"] = nil
            require("ClassColor")
        end)

        it("returns class-colored name with bank alt suffix", function()
            local text = B.GetTooltipText("Banker", "MAGE")
            assert.truthy(text:find("|cff"))
            assert.truthy(text:find("Banker"))
            assert.truthy(text:find(" is a bank alt$"))
        end)

        it("uses white name when classFile is nil", function()
            local text = B.GetTooltipText("Banker", nil)
            assert.are.equal("|cffffffffBanker|r is a bank alt", text)
        end)
    end)

    describe("PresentTooltip", function()
        local owner
        local lines

        before_each(function()
            lines = {}
            owner = { anchor = nil }
            _G.GameTooltip = {
                SetOwner = function(_, frame, anchor)
                    owner.anchor = anchor
                end,
                ClearLines = function() end,
                AddLine = function(_, text, r, g, b)
                    lines[#lines + 1] = { text = text, r = r, g = g, b = b }
                end,
                Show = function() end,
                Hide = function() end,
            }
            _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
                WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
            }
            package.loaded["ClassColor"] = nil
            require("ClassColor")
        end)

        it("shows tooltip only for bank alts", function()
            B.Set("Banker", "RealmA", true)
            assert.is_true(B.PresentTooltip(owner, "ANCHOR_BOTTOMLEFT", "Banker", "RealmA", "WARRIOR"))
            assert.truthy(lines[1].text:find("Banker"))
            assert.truthy(lines[1].text:find(" is a bank alt"))
            assert.are.equal("ANCHOR_BOTTOMLEFT", owner.anchor)
        end)

        it("adds a gray Click to configure hint", function()
            B.Set("Banker", "RealmA", true)
            assert.is_true(B.PresentTooltip(owner, "ANCHOR_BOTTOMLEFT", "Banker", "RealmA", "WARRIOR"))
            assert.are.equal(2, #lines)
            assert.are.equal("Click to configure", lines[2].text)
            assert.are.equal(0.5, lines[2].r)
            assert.are.equal(0.5, lines[2].g)
            assert.are.equal(0.5, lines[2].b)
        end)

        it("returns false when character is not a bank alt", function()
            assert.is_false(B.PresentTooltip(owner, "ANCHOR_BOTTOMLEFT", "Alice", "RealmA", "WARRIOR"))
            assert.are.equal(0, #lines)
        end)
    end)
end)
