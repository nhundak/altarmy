--[[ Unit tests for StockpilePlan.lua — run: npm test ]]

describe("StockpilePlan", function()
  local SP

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("StockpilePlan")
    SP = AltArmy.StockpilePlan
    assert.truthy(SP)
  end)

  local function stacks(list)
    local out = {}
    for i, c in ipairs(list) do
      out[#out + 1] = { bagID = 0, slot = i, count = c }
    end
    return out
  end

  local function build(need, list, opts)
    opts = opts or {}
    opts.stackLimit = opts.stackLimit or 20
    opts.maxAttachments = opts.maxAttachments or 12
    opts.emptySlotsAvailable = opts.emptySlotsAvailable == nil and 20 or opts.emptySlotsAvailable
    opts.allowMerge = opts.allowMerge ~= false
    opts.preferExact = opts.preferExact ~= false
    return SP.BuildItemPlan(need, stacks(list), opts)
  end

  it("A1: need==0 has empty plan", function()
    local r = build(0, { 5 })
    assert.is_true(r.ok)
    assert.are.equal(0, r.attachments)
    assert.are.equal(0, #r.ops)
  end)

  it("B1: prefers exact stack over splitting", function()
    local r = build(2, { 2, 13 })
    assert.is_true(r.ok)
    assert.are.equal(1, r.attachments)
    assert.are.equal("attach", r.ops[1].op)
    assert.are.equal(1, r.ops[1].slot)
  end)

  it("C1: splits when only larger stack exists", function()
    local r = build(2, { 13 }, { emptySlotsAvailable = 1 })
    assert.is_true(r.ok)
    assert.are.equal(1, r.attachments)
    assert.are.equal("split_attach", r.ops[1].op)
    assert.are.equal(2, r.ops[1].count)
  end)

  it("D1: can attach then split when a larger stack remains", function()
    local r = build(10, { 6, 6 }, { emptySlotsAvailable = 1 })
    assert.is_true(r.ok)
    local seenMerge, seenSplit = false, false
    for _, op in ipairs(r.ops) do
      if op.op == "merge" then seenMerge = true end
      if op.op == "split_attach" then seenSplit = true end
    end
    -- Preferred: top up an existing 6-stack to 10 with a split, then attach once.
    assert.is_false(seenMerge)
    assert.is_false(seenSplit)
    assert.are.equal(1, r.attachments)
    assert.are.equal("split_merge_attach", r.ops[1].op)
    assert.are.equal(4, r.ops[1].count)
    assert.are.equal(10, r.ops[1].finalCount)
  end)

  it("D2: merges small stacks when no single stack can be split to finish remainder", function()
    -- With a 1-attachment cap, we must merge to one stack then split/attach.
    local r = build(10, { 6, 3, 3 }, { emptySlotsAvailable = 1, maxAttachments = 1 })
    assert.is_true(r.ok)
    local seenMerge, seenSplit = false, false
    for _, op in ipairs(r.ops) do
      if op.op == "merge" then seenMerge = true end
      if op.op == "split_attach" then seenSplit = true end
    end
    assert.is_true(seenMerge)
    assert.is_true(seenSplit)
  end)

  it("A3/E1: can satisfy with multiple stacks without split", function()
    local r = build(10, { 6, 4, 20 })
    assert.is_true(r.ok)
    -- Preferred: top up 6 with 4 split from 20 (or use 4 directly), attaching once.
    assert.are.equal(1, r.attachments)
  end)

  it("tops up existing small stack before attaching", function()
    local r = build(2, { 8, 1 }, { emptySlotsAvailable = 1 })
    assert.is_true(r.ok)
    assert.are.equal(1, r.attachments)
    assert.are.equal("split_merge_attach", r.ops[1].op)
    assert.are.equal(1, r.ops[1].count) -- split 1 from large stack into the existing 1 stack
    assert.are.equal(2, r.ops[1].finalCount)
  end)

  it("H2: uses existing full stack first, then remainder", function()
    local r = build(37, { 20, 20, 13, 4 }, { stackLimit = 20 })
    assert.is_true(r.ok)
    -- Preferred: attach one full 20, then top up 13 to 17 and attach once (2 attachments total)
    assert.are.equal(2, r.attachments)
    assert.are.equal("attach", r.ops[1].op)
    assert.are.equal(20, r.ops[1].count)
  end)

  it("F1: fails when split needed but no empty slots", function()
    local r = build(2, { 13 }, { emptySlotsAvailable = 0 })
    assert.is_false(r.ok)
    assert.are.equal("no_empty_slot_for_split", r.reason)
  end)

  it("F4: fails when attachments exceed maxAttachments", function()
    -- With stackLimit 5, need 13 requires at least 3 attachments (5+5+3).
    local r = build(
      13,
      { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
      { maxAttachments = 2, stackLimit = 5 }
    )
    assert.is_false(r.ok)
    assert.are.equal("too_many_attachments", r.reason)
  end)
end)

