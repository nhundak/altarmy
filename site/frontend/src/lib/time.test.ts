import { describe, expect, it } from 'vitest'
import { formatCoords } from './time'

describe('formatCoords', () => {
  it('reads a spot to one decimal', () => {
    expect(formatCoords(55.94, 62.7)).toBe('55.9, 62.7')
    expect(formatCoords(50, 70.44)).toBe('50.0, 70.4')
  })
})
