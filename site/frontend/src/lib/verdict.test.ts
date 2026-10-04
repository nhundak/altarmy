import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { reasonText, verdictTitle, verdictWord } from './verdict'

describe('verdict', () => {
  it('words the most actionable reason for the chip', () => {
    const lone = { ...robeResult, verdict: 'unproven' as const, verdict_reasons: ['lone', 'thin'] }
    expect(verdictWord(lone)).toBe('an asking price, not a price')
    expect(verdictWord({ ...robeResult, verdict_reasons: [], buy_flags: ['short'] })).toBe('it buys more than is listed')
    expect(verdictWord(robeResult)).toBe('')
  })

  it('spells the whole verdict out for a tooltip', () => {
    expect(verdictTitle(robeResult)).toBe('Steady to sell: it surely sells')
    const unsure = { ...robeResult, verdict: 'likely' as const, verdict_reasons: ['unwatched'], buy_flags: ['just_listed'] }
    expect(verdictTitle(unsure)).toBe(
      'Likely to sell: sales unknown: nobody scanned twice within 30 minutes lately; its cheapest reagent was just listed, and may be gone',
    )
    expect(reasonText('mystery')).toBe('mystery')
  })
})
