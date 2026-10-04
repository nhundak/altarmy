import { describe, expect, it } from 'vitest'
import { bonusNote, discountLabel, discountNote } from './talents'

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

  it('says which discounts a vendor buy got, without numbers', () => {
    expect(discountLabel(10, 0)).toBe('after bartering discount')
    expect(discountLabel(0, 10)).toBe('after reputation discount')
    expect(discountLabel(5, 10)).toBe('after reputation and bartering discount')
    expect(discountLabel(0, 0)).toBe('')
  })

  it('names the Master Chef bonus, rounded', () => {
    expect(bonusNote(0.3)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0.30000000000000004)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0)).toBe('')
  })
})
