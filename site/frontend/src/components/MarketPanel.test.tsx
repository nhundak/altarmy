import { describe, expect, it } from 'vitest'
import { seenSold } from './MarketPanel'

describe('seenSold', () => {
  it('says what was seen sold against how long the house was watched', () => {
    expect(seenSold(11, 19, 4)).toBe('At least 11 seen sold in 19 hours watched, over 4 scan pairs')
    expect(seenSold(6, 2, 1)).toBe('6 seen sold in 2 hours watched, all between one pair of scans: maybe a single buyer')
    expect(seenSold(0, 5, null)).toBe('None seen sold in 5 hours watched')
    expect(seenSold(0, 0, null)).toMatch(/^Sales here aren't watched yet/)
  })
})
