import { describe, expect, it } from 'vitest'
import {
  BARTERING,
  MASTER_CHEF,
  WORKING_OVERTIME,
  bonusNote,
  craftingTalents,
  discountLabel,
  discountNote,
  talentNote,
} from './talents'

describe('talent notes', () => {
  it('names the Bartering discount', () => {
    expect(discountNote(10)).toBe('Bartering −10%')
    expect(discountNote(0)).toBe('')
  })

  it('names the reputation discount and whose vendors give it', () => {
    expect(discountNote(0, 10, 'Orgrimmar')).toBe('Orgrimmar reputation −10%')
    expect(discountNote(10, 10, 'Darkspear Trolls')).toBe('Bartering −10%, Darkspear Trolls reputation −10%')
    expect(discountNote(0, 10)).toBe('Reputation −10%')
    expect(discountNote(0, 0, 'Orgrimmar')).toBe('')
  })

  it('says a vendor buy got a discount, without which or how much', () => {
    expect(discountLabel(10, 0)).toBe('after discount')
    expect(discountLabel(0, 10)).toBe('after discount')
    expect(discountLabel(5, 10)).toBe('after discount')
    expect(discountLabel(0, 0)).toBe('')
  })

  it('names the Master Chef bonus, rounded', () => {
    expect(bonusNote(0.3)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0.30000000000000004)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0)).toBe('')
  })
})

describe('crafting talents', () => {
  const talents = [
    { spell_id: MASTER_CHEF, name: 'Master Chef', rank: 3, max_rank: 5 },
    { spell_id: BARTERING, name: 'Bartering', rank: 2, max_rank: 2 },
    { spell_id: WORKING_OVERTIME, name: 'Working Overtime', rank: 0, max_rank: 5 },
  ]

  it('keeps the ranked ones that matter to the profession, Master Chef only for Cooking', () => {
    expect(craftingTalents(talents, 'Cooking').map((t) => t.name)).toEqual(['Bartering', 'Master Chef'])
    expect(craftingTalents(talents, 'Tailoring').map((t) => t.name)).toEqual(['Bartering'])
  })

  it('says what each does at its rank', () => {
    const [bartering, chef] = craftingTalents(talents, 'Cooking')
    expect(talentNote(bartering!)).toBe('Reduces the gold price of items from all vendors by 10%')
    expect(talentNote(chef!)).toBe('Your cooking recipes have a 30% chance to create an extra result')
    expect(talentNote({ spellId: WORKING_OVERTIME, name: 'Working Overtime', rank: 1, maxRank: 5 })).toBe(
      'Increases your chance to gain a skill increase by 4%',
    )
  })
})
