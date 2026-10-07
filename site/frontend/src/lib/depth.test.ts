import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { depthSteps, priceRange, profitAt, scale } from './depth'

const level = (price: number, quantity: number, counted = true, more = false) => ({
  price,
  quantity,
  counted,
  more,
  listings: 2,
  age: 1,
})

describe('depthSteps', () => {
  const levels = [level(90, 2, false), level(100, 4), level(120, 5), level(150, 9, true, true)]

  it('lays the levels end to end, the plan’s units put in after those at its price or under', () => {
    const { steps, total } = depthSteps(levels, { insert: { price: 100, units: 3 } })
    expect(steps.map((s) => [s.kind, s.price, s.x0, s.x1])).toEqual([
      ['uncounted', 90, 0, 2],
      ['level', 100, 2, 6],
      ['you', 100, 6, 9],
      ['level', 120, 9, 14],
      ['tail', 150, 14, 23],
    ])
    expect(total).toBe(23)
  })

  it('puts the plan’s units last when every level is cheaper, and marks what is bought', () => {
    expect(depthSteps(levels, { insert: { price: 200, units: 1 } }).steps.at(-1)).toMatchObject({ kind: 'you', x0: 20 })
    expect(depthSteps(levels, { taken: [0, 4, 1, 0] }).steps.map((s) => s.taken)).toEqual([0, 4, 1, 0])
  })
})

describe('ranges and scales', () => {
  it('leaves room around the prices, never under 0', () => {
    const { lo, hi } = priceRange([100, 200])
    expect(lo).toBeLessThan(100)
    expect(lo).toBeGreaterThanOrEqual(0)
    expect(hi).toBeGreaterThan(200)
    expect(priceRange([1]).lo).toBe(0)
  })

  it('maps a domain onto a range, a flat one to the middle', () => {
    expect(scale(0, 10, 0, 100)(5)).toBe(50)
    expect(scale(3, 3, 0, 100)(3)).toBe(50)
  })
})

describe('profitAt', () => {
  it('moves the plan’s own AH profit by what each unit brings after the cut', () => {
    // the robe's AH sale makes 175 at 475; one robe at 575 brings 95 more
    expect(profitAt(robeResult, 475, 0.05, 475)).toBe(175)
    expect(profitAt(robeResult, 475, 0.05, 575)).toBe(270)
    expect(profitAt({ ...robeResult, sell_options: [] }, 475, 0.05, 500)).toBeNull()
  })
})
