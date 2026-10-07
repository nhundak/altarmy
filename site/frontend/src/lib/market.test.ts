import { describe, expect, it } from 'vitest'
import type { FlowNode, ItemInfo, RankResult } from '../api/client'
import { linen, makeItem, robe, thread } from '../test/items'
import { bought, robeResult } from '../test/results'
import { cue, defaultItem, headerSummary, marketItems, seenSold, walkLadder, type MarketItem } from './market'

const level = (price: number, quantity: number, counted = true) => ({
  price,
  quantity,
  counted,
  more: false,
  listings: 1,
  age: 1,
})

// Linen bought twice (10 for the robe, 6 more for a bolt made on the way), and dust from disenchanting the robe.
const bolt: FlowNode = {
  ...bought(5, 'Bolt of Linen', 3, 120),
  source: '',
  via: 'Bolt of Linen',
  crafts: 3,
  made: 3,
  option: 'craft:7',
  options: [
    { key: 'craft:7', cost: 120, source: '', via: 'Bolt of Linen', crafter: '', seconds: 0, convert: false },
    { key: 'ah', cost: 150, source: 'ah', via: '', crafter: '', seconds: 0, convert: false },
  ],
  inputs: [bought(1, 'Linen Cloth', 6, 120)],
}
const dusty: RankResult = {
  ...robeResult,
  cost: 420,
  tree: { ...robeResult.tree, cost: 420, inputs: [...robeResult.tree.inputs, bolt] },
  exits: [
    ...robeResult.exits,
    {
      kind: 'disenchant',
      value: 100,
      postage: 0,
      mail_to: '',
      materials: [
        { item_id: 10, name: 'Strange Dust', chance: 1, min_count: 1, max_count: 3, expected: 2, value: 50 },
      ],
    },
  ],
}

describe('marketItems', () => {
  it('lists what is bought (costliest first), then what is sold', () => {
    const list = marketItems(robeResult)
    expect(list.map((m) => [m.name, m.group, m.quantity, m.cost, m.source])).toEqual([
      ['Linen Cloth', 'buy', 10, 200, 'ah'],
      ['Coarse Thread', 'buy', 1, 100, 'vendor'],
      ['Green Robe', 'sell', 1, null, ''],
    ])
    expect(list[0]!.share).toBeCloseTo(2 / 3)
  })

  it('sums an item bought by several branches, then what is made, sold and disenchanted', () => {
    const list = marketItems(dusty)
    expect(list.map((m) => [m.name, m.group, m.quantity])).toEqual([
      ['Linen Cloth', 'buy', 16],
      ['Coarse Thread', 'buy', 1],
      ['Bolt of Linen', 'make', 3],
      ['Green Robe', 'sell', 1],
      ['Strange Dust', 'disenchant', 2],
    ])
    expect(list[0]).toMatchObject({ cost: 320, shared: true })
  })

  it('sells nothing for an enchant cast for the skill point', () => {
    const enchant = { ...robeResult, best_exit: 'skill', tree: { ...robeResult.tree, item_id: 0, enchant: true } }
    expect(marketItems(enchant).map((m) => m.group)).toEqual(['buy', 'buy'])
  })
})

describe('defaultItem', () => {
  it('opens a gold row on what is sold, or the likeliest material when it is likely disenchanted', () => {
    expect(defaultItem(marketItems(dusty), dusty, 'gold')).toBe(3)
    const disenchanted = { ...dusty, likely_exit: 'disenchant' }
    expect(defaultItem(marketItems(disenchanted), disenchanted, 'gold')).toBe(10)
  })

  it('opens a skill run on the costliest thing bought', () => {
    expect(defaultItem(marketItems(dusty), dusty, 'skill')).toBe(1)
    expect(defaultItem([], dusty, 'skill')).toBeNull()
  })
})

describe('walkLadder', () => {
  const levels = [level(10, 2, false), level(20, 3), level(25, 4)]

  it('buys up the counted levels, the units short priced at the dearest', () => {
    expect(walkLadder(levels, 10)).toEqual({
      taken: [0, 3, 4],
      cost: 3 * 20 + 4 * 25 + 3 * 25,
      last: 25,
      average: 24,
      short: 3,
      dearest: 25,
    })
  })

  it('starts after the units another branch took', () => {
    expect(walkLadder(levels, 4, 2)).toMatchObject({ taken: [0, 1, 3], short: 0, last: 25 })
  })

  it('has nothing to say without levels', () => {
    expect(walkLadder([], 5)).toMatchObject({ average: null, last: null, short: 5 })
  })
})

describe('cue', () => {
  const items = (over: Partial<ItemInfo>) => ({ '1': { ...linen, ...over }, '2': thread, '3': robe })
  const linenBuy = (over: Partial<MarketItem> = {}) => ({ ...marketItems(robeResult)[0]!, ...over })
  const ladder = [level(22, 20)] // ten bought at 22 each

  it('says first when the listings are short of what is bought', () => {
    const got = cue(linenBuy({ short: 4 }), robeResult, items({ listed: false }))
    expect(got).toMatchObject({ text: '4 short', tone: 'bad' })
  })

  it('says when nothing is listed', () => {
    expect(cue(linenBuy(), robeResult, items({ listed: false }))).toMatchObject({ text: 'not listed' })
  })

  it('compares with the usual price only after 3 days of scans and a move of 5% or more', () => {
    const at = (median: number, days: number) =>
      cue(linenBuy(), robeResult, items({ ah_levels: ladder, median_7d: median, scans_7d: days }))?.text ?? null
    expect(at(20, 4)).toBe('▲10%')
    expect(at(20, 2)).toBeNull()
    expect(at(21, 4)).toBeNull() // under 5%
    expect(cue(linenBuy(), robeResult, items({ ah_levels: ladder, median_7d: 20, scans_7d: 4 }))?.tone).toBe('bad')
  })

  it('calls a cheaper sale bad and a cheaper buy good', () => {
    const sell = marketItems(robeResult).find((m) => m.group === 'sell')!
    const cheap = { ...items({}), '3': { ...robe, ah_sell_price: 900, median_7d: 1000, scans_7d: 5 } }
    expect(cue(sell, robeResult, cheap)).toMatchObject({ text: '▼10%', tone: 'bad' })
    const bargain = cue(linenBuy(), robeResult, items({ ah_levels: ladder, median_7d: 25, scans_7d: 4 }))
    expect(bargain).toMatchObject({ text: '▼12%', tone: 'good' })
  })

  it('says when disenchanting floods a material', () => {
    const dust = marketItems(dusty).find((m) => m.group === 'disenchant')!
    const listed = (n: number) =>
      cue(dust, dusty, { '10': makeItem({ id: 10, name: 'Strange Dust', ah_quantity: n, ah_price: 40 }) })
    expect(listed(3)).toMatchObject({ text: 'floods', label: 'Disenchanting adds ~2 to the 3 listed' })
    expect(listed(30)).toBeNull()
  })

  it('has nothing to say of what a vendor sells or what is made', () => {
    expect(cue(marketItems(robeResult)[1]!, robeResult, items({}))).toBeNull()
  })
})

describe('headerSummary', () => {
  const posted = { ...robeResult, best_exit: 'ah', likely_exit: 'ah', crafts: 10, excess_units: 9 }
  const priced = { '1': linen, '2': thread, '3': { ...robe, ah_sell_price: 950 } }

  it('says what selling on the auction house counts on', () => {
    expect(headerSummary(posted, marketItems(posted), priced, 'gold')).toEqual({
      kind: 'ah',
      price: 950,
      units: 1,
      of: 10,
      flag: null,
    })
  })

  it('says how it sells otherwise, and what a skill run buys', () => {
    expect(headerSummary(robeResult, marketItems(robeResult), priced, 'gold')).toMatchObject({ kind: 'exit', exit: 'vendor' })
    expect(headerSummary(robeResult, marketItems(robeResult), priced, 'skill')).toMatchObject({
      kind: 'skill',
      reagents: 2,
      cost: 300,
    })
  })

  it('names the item most of the cost goes on, when its market has a cue', () => {
    const short = { ...posted, tree: { ...posted.tree, inputs: [{ ...bought(1, 'Linen Cloth', 10, 200), short: 4 }, posted.tree.inputs[1]!] } }
    expect(headerSummary(short, marketItems(short), priced, 'gold').flag).toMatchObject({
      name: 'Linen Cloth',
      cue: { text: '4 short' },
    })
  })
})

describe('seenSold', () => {
  it('says what was seen sold against how long the house was watched', () => {
    expect(seenSold(11, 19, 4)).toBe('At least 11 seen sold in 19 hours watched, over 4 scan pairs')
    expect(seenSold(6, 2, 1)).toBe('6 seen sold in 2 hours watched, all between one pair of scans: maybe a single buyer')
    expect(seenSold(0, 5, null)).toBe('None seen sold in 5 hours watched')
    expect(seenSold(3, 1 / 3, 2)).toBe('At least 3 seen sold in 0.3 hours watched, over 2 scan pairs')
    expect(seenSold(0, 0, null)).toMatch(/^Sales here aren't watched yet/)
  })
})
