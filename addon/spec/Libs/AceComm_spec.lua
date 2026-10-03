--[[
  Unit tests for AltArmy's patched AceComm-3.0 receive path.
  Run from project root: npm test
]]

describe("AceComm-3.0 CHAT_MSG_ADDON secret-value guard", function()
    local SECRET = "<secret>"
    local onEvent
    local AceComm
    local ambiguateCalls
    local received

    setup(function()
        _G.LibStub = nil
        _G.CreateFrame = function()
            return {
                SetScript = function(_, script, handler)
                    if script == "OnEvent" then onEvent = handler end
                end,
                UnregisterAllEvents = function() end,
                RegisterEvent = function() end,
            }
        end
        _G.Ambiguate = function(name)
            ambiguateCalls = ambiguateCalls + 1
            return name
        end
        _G.ChatThrottleLib = _G.ChatThrottleLib or {}
        _G.securecallfunction = _G.securecallfunction or function(f, ...) return f(...) end
        _G.C_ChatInfo = _G.C_ChatInfo or { RegisterAddonMessagePrefix = function() return true end }
        dofile("AltArmy_TBC/Libs/LibStub/LibStub.lua")
        dofile("AltArmy_TBC/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
        dofile("AltArmy_TBC/Libs/AceComm-3.0/AceComm-3.0.lua")
        AceComm = _G.LibStub("AceComm-3.0")
        local obj = {}
        AceComm:Embed(obj)
        obj:RegisterComm("AATest", function(_, message, _, sender)
            received[#received + 1] = { message = message, sender = sender }
        end)
    end)

    teardown(function()
        _G.canaccessvalue = nil
        _G.Ambiguate = nil
    end)

    before_each(function()
        ambiguateCalls = 0
        received = {}
        _G.canaccessvalue = function(v) return v ~= SECRET end
    end)

    it("drops a message whose text is secret", function()
        onEvent(nil, "CHAT_MSG_ADDON", "AATest", SECRET, "GUILD", "Bob")
        assert.are.equal(0, #received)
        assert.are.equal(0, ambiguateCalls)
    end)

    it("drops a message whose sender is secret", function()
        onEvent(nil, "CHAT_MSG_ADDON", "AATest", "hello", "GUILD", SECRET)
        assert.are.equal(0, #received)
        assert.are.equal(0, ambiguateCalls)
    end)

    it("drops a message whose prefix is secret", function()
        onEvent(nil, "CHAT_MSG_ADDON", SECRET, "hello", "GUILD", "Bob")
        assert.are.equal(0, #received)
    end)

    it("still delivers plain messages", function()
        onEvent(nil, "CHAT_MSG_ADDON", "AATest", "hello", "GUILD", "Bob")
        assert.are.equal(1, #received)
        assert.are.equal("hello", received[1].message)
        assert.are.equal("Bob", received[1].sender)
    end)

    it("delivers plain messages on clients without canaccessvalue", function()
        _G.canaccessvalue = nil
        onEvent(nil, "CHAT_MSG_ADDON", "AATest", "hello", "GUILD", "Bob")
        assert.are.equal(1, #received)
    end)
end)
