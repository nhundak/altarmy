import { describe, expect, it } from 'vitest'
import { formatMoney, formatRoi, goldToCopper } from './money'

describe('goldToCopper', () => {
  it('rounds to whole copper', () => {
    expect(goldToCopper(1.5)).toBe(15000)
    expect(goldToCopper(0.00016)).toBe(2)
  })
})

describe('formatRoi', () => {
  it('shows a whole percentage', () => {
    expect(formatRoi(2 / 3)).toBe('67%')
    expect(formatRoi(0)).toBe('0%')
  })
})

describe('formatMoney', () => {
  it('writes coins as letters, dropping what the coin display drops', () => {
    expect(formatMoney(276242)).toBe('27g 62s 42c')
    expect(formatMoney(-500)).toBe('-5s 0c')
    expect(formatMoney(12345678)).toBe('1234g 56s')
  })
})
