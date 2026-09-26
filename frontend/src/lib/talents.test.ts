import { describe, expect, it } from 'vitest'
import { bonusNote, discountNote } from './talents'

describe('talent notes', () => {
  it('names the Bartering discount', () => {
    expect(discountNote(10)).toBe('Bartering −10%')
    expect(discountNote(0)).toBe('')
  })

  it('names the Master Chef bonus, rounded', () => {
    expect(bonusNote(0.3)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0.30000000000000004)).toBe('+0.3 expected from Master Chef')
    expect(bonusNote(0)).toBe('')
  })
})
