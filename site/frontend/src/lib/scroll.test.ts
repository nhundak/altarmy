import { describe, expect, it } from 'vitest'
import { scrollTarget } from './scroll'

describe('scrollTarget', () => {
  it('moves as little as it takes to show the whole box, with a margin', () => {
    expect(scrollTarget(100, 200, 0, 800)).toBeNull() // already in view
    expect(scrollTarget(700, 300, 0, 800)).toBe(216) // its bottom (1000) plus the margin, at the window's bottom
    expect(scrollTarget(100, 200, 500, 800)).toBe(84) // above: its top, less the margin
  })

  it('shows the top of a box taller than the window', () => {
    expect(scrollTarget(700, 2000, 0, 800)).toBe(684)
    expect(scrollTarget(10, 2000, 300, 800)).toBe(0) // never above the page
  })
})
