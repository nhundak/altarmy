--[[ Unit tests for AuctionScanButton.lua — run: npm test ]]

describe("AuctionScanButton", function()
    local Btn

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["AuctionScanButton"] = nil
        require("AuctionScanButton")
        Btn = AltArmy.AuctionScanButton
        assert.truthy(Btn)
    end)

    it("offers a scan when the client allows one", function()
        assert.same({ "Alt Army scan", true }, { Btn.Label("idle", 0, 0) })
    end)

    it("counts the cooldown down", function()
        assert.same({ "Scan in 14:59", false }, { Btn.Label("idle", 0, 899) })
        assert.same({ "Scan in 0:05", false }, { Btn.Label("idle", 0, 5) })
    end)

    it("says it is waiting for the listings", function()
        assert.same({ "Scanning...", false }, { Btn.Label("waiting", 0, 900) })
    end)

    it("shows how much is read", function()
        assert.same({ "Scanning 45%", false }, { Btn.Label("reading", 0.456, 900) })
    end)

    it("offers a summary scan during the cooldown when the client has one", function()
        assert.same({ "Alt Army scan", true }, { Btn.Label("idle", 0, 899, true) })
    end)

    it("says it is scanning when a summary has no progress to show", function()
        assert.same({ "Scanning...", false }, { Btn.Label("reading", nil, 0, true) })
    end)

    it("says in its tooltip which scan a click runs", function()
        assert.truthy(Btn.TooltipText("full", 0):find("full scan"))
        local text = Btn.TooltipText("summary", 125)
        assert.truthy(text:find("summary scan"))
        assert.truthy(text:find("2:05"))
        assert.is_nil(Btn.TooltipText("summary", 0):find("allowed in"))
    end)

    it("opens the options on the automatic scan checkbox", function()
        local opened
        AltArmy.OpenInterfaceOptions = function(tab, opts) opened = { tab, opts.flash } end
        Btn.OpenSettings()
        assert.same({ "general", "autoScan" }, opened)
        AltArmy.OpenInterfaceOptions = nil
    end)
end)
