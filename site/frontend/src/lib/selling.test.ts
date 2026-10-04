import { describe, expect, it } from 'vitest'
import type { RankResult } from '../api/client'
import { linen, makeItem } from '../test/items'
import { robeResult } from '../test/results'
import { breakEven, countedOn, fallback, floodCheck, floor } from './selling'

// the robe: costs 300 to make one, a vendor pays 500, the AH nets 475 of a 500 listing
const robe: RankResult = { ...robeResult, best_exit: 'ah' }

describe('selling', () => {
  it('says under what price another exit pays more', () => {
    expect(fallback(robe)).toEqual({ kind: 'vendor', value: 500 })
    expect(floor(robe, 0.05)).toBe(527) // 500 / 0.95, rounded up
    expect(floor({ exits: [{ kind: 'ah', value: 475, materials: [], postage: 0, mail_to: '' }] }, 0.05)).toBeNull()
  })

  it('says under what price the session loses gold', () => {
    expect(breakEven(robe, 0.05)).toBe(316) // 300 / 0.95
    expect(breakEven({ ...robe, cost: 3000, crafts: 10 }, 0.05)).toBe(316)
  })

  it('says what the plan counted on, and for how many', () => {
    const items = { 3: makeItem({ id: 3, name: 'Green Robe', ah_sell_price: 480 }) }
    expect(countedOn({ ...robe, crafts: 5, excess_units: 3 }, items)).toEqual({ price: 480, units: 2, of: 5 })
  })

  it('says what disenchanting adds to each material listed', () => {
    const de: RankResult = {
      ...robe,
      crafts: 5,
      exits: [
        {
          kind: 'disenchant',
          value: 900,
          postage: 0,
          mail_to: '',
          materials: [{ item_id: 1, name: 'Linen Cloth', chance: 0.8, min_count: 1, max_count: 3, value: 700 }],
        },
      ],
    }
    expect(floodCheck(de, { 1: { ...linen, ah_quantity: 90 } })).toEqual([
      { itemId: 1, name: 'Linen Cloth', adds: 8, listed: 90 },
    ])
    expect(floodCheck(robe, {})).toEqual([])
  })
})
