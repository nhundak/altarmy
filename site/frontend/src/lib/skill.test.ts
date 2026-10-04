import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { craftUntil, perPoint, runLead, runText, scaleRun, stepsText } from './skill'

describe('perPoint', () => {
  it('is what an expected skill point costs, negative when the run earns', () => {
    expect(perPoint({ ...robeResult, profit: -300, skill_ups: 3 })).toBe(100)
    expect(perPoint({ ...robeResult, profit: 300, skill_ups: 3 })).toBe(-100)
    expect(perPoint({ ...robeResult, skill_ups: 0 })).toBeNull()
  })
})

describe('runText', () => {
  it('says to which skill to craft, how many times, and why then', () => {
    const run = { crafts: 17, stop_skill: 85, stop_reason: 'rival', overtaken_by: 'Heavy Copper Maul' }
    expect(runText(run)).toBe(
      'Craft until 85 skill (~17 times), at which point Heavy Copper Maul becomes a cheaper option',
    )
    expect(runText({ ...run, stop_reason: 'trivial' })).toBe(
      'Craft until 85 skill (~17 times), at which point this recipe becomes trivial',
    )
    expect(runText({ ...run, stop_reason: 'cap' })).toBe(
      'Craft until 85 skill (~17 times), at which point you reach your skill cap',
    )
    expect(runText({ ...run, crafts: 100, stop_reason: 'ceiling' })).toBe('Craft until 85 skill (~100 times)')
    expect(runLead({ crafts: 1, stop_skill: 85 })).toBe('Craft until 85 skill (once)')
    expect(runLead({ crafts: 3, stop_skill: 0 })).toBe('Craft ~3 times')
  })

  it('says to which skill a run in the table goes, and in how many crafts', () => {
    expect(craftUntil({ crafts: 17, stop_skill: 110 })).toBe('110 (~17 crafts)')
    expect(craftUntil({ crafts: 1, stop_skill: 110 })).toBe('110 (1 craft)')
    expect(craftUntil({ crafts: 3, stop_skill: 0 })).toBe('~3 crafts')
  })
})

describe('stepsText', () => {
  it('writes the plan as a plain checklist', () => {
    const steps: Parameters<typeof stepsText>[1] = [
      { action: 'buy', name: 'Linen Cloth', quantity: 10, via: 'ah', who: 'Bob', enchant: false },
      { action: 'gather', name: 'Wool Cloth', quantity: 4, via: '', who: 'Bob', enchant: false },
      { action: 'craft', name: 'Green Robe', quantity: 1, via: 'Green Robe', who: 'Bob', enchant: false },
      { action: 'sell', name: 'Green Robe', quantity: 1, via: 'vendor', who: 'Bob', enchant: false },
    ]
    expect(stepsText('Tailoring: Green Robe', steps)).toBe(
      [
        'Tailoring: Green Robe',
        '1. Bob: Buy 10x Linen Cloth on the AH',
        '2. Bob: Gather 4x Wool Cloth',
        '3. Bob: Craft 1x Green Robe',
        '4. Bob: Sell back 1x Green Robe to a vendor',
      ].join('\n'),
    )
  })
})

describe('scaleRun', () => {
  it('scales a plan to another number of crafts, quantities rounded up', () => {
    const plan = { ...robeResult, crafts: 4 }
    const more = scaleRun(plan, 6)
    expect(more.crafts).toBe(6)
    expect(more.steps.map((s) => [s.name, s.quantity, s.value])).toEqual([
      ['Linen Cloth', 15, -300],
      ['Coarse Thread', 2, -150],
      ['Green Robe', 2, 0],
      ['Green Robe', 2, 750],
    ])
    expect(scaleRun(plan, 4)).toBe(plan)
  })
})
