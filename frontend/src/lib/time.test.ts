import { describe, expect, it } from 'vitest'
import { breakdownParts, formatSeconds } from './time'

describe('formatSeconds', () => {
  it.each([
    [0, '0 s'],
    [0.34, '0.3 s'],
    [3.5, '3.5 s'],
    [9.96, '10 s'],
    [42.4, '42 s'],
    [60, '1 min'],
    [245, '4 min 5 s'],
    [3600, '1 h'],
    [4830, '1 h 20 min'],
  ])('%s seconds read %s', (seconds, text) => {
    expect(formatSeconds(seconds)).toBe(text)
  })
})

describe('breakdownParts', () => {
  it('lists the parts that take time, longest first', () => {
    expect(breakdownParts({ travel: 90, switch: 0, craft: 120, ah: 12, mail: 0.01 })).toEqual([
      'crafting 2 min',
      'running 1 min 30 s',
      'auction house 12 s',
    ])
  })
})
