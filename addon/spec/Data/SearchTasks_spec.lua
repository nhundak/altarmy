--[[ Unit tests for SearchTasks.lua — budgeted task queue. ]]

describe("SearchTasks", function()
    local ST

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = _G.CreateFrame or function()
            local f = {
                scripts = {},
            }
            function f:SetScript(event, fn)
                self.scripts[event] = fn
            end
            function f:GetScript(event)
                return self.scripts[event]
            end
            return f
        end
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["SearchTasks"] = nil
        require("SearchTasks")
        ST = AltArmy.SearchTasks
        assert.truthy(ST)
    end)

    before_each(function()
        ST.ResetForTests()
    end)

    it("BumpGeneration cancels pending work", function()
        local ran = false
        ST.Enqueue(function()
            ran = true
            return true
        end)
        ST.BumpGeneration()
        ST.TickForTests()
        assert.is_false(ran)
    end)

    it("runs enqueued steps until complete", function()
        local n = 0
        ST.Enqueue(function()
            n = n + 1
            return n >= 3
        end)
        ST.TickForTests()
        ST.TickForTests()
        ST.TickForTests()
        assert.are.equal(3, n)
        assert.is_false(ST.IsBusy())
    end)

    it("runs tasks in FIFO order", function()
        local order = {}
        ST.Enqueue(function()
            order[#order + 1] = "a"
            return true
        end)
        ST.Enqueue(function()
            order[#order + 1] = "b"
            return true
        end)
        ST.TickForTests()
        ST.TickForTests()
        assert.are.same({ "a", "b" }, order)
    end)
end)
