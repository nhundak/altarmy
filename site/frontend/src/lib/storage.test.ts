import { renderHook } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { z } from 'zod'
import { parseStored, useStoredState, writeStored } from './storage'

describe('parseStored', () => {
  const schema = z.array(z.string())

  it('returns valid stored values', () => {
    expect(parseStored(schema, '["Tailoring"]', [])).toEqual(['Tailoring'])
  })

  it('falls back on missing, unparsable or invalid values', () => {
    expect(parseStored(schema, undefined, ['x'])).toEqual(['x'])
    expect(parseStored(schema, 'not json', ['x'])).toEqual(['x'])
    expect(parseStored(schema, '[1, 2]', ['x'])).toEqual(['x'])
  })
})

describe('useStoredState', () => {
  const schema = z.number()

  it('starts from a legacy key while its own is unset, then keeps its own', () => {
    localStorage.setItem('old', '5')
    const first = renderHook(() => useStoredState('new', schema, 1, 'old'))
    expect(first.result.current[0]).toBe(5)
    first.unmount()
    localStorage.setItem('new', '7')
    const second = renderHook(() => useStoredState('new', schema, 1, 'old'))
    expect(second.result.current[0]).toBe(7)
    expect(localStorage.getItem('old')).toBe('5') // the legacy key is only read
  })

  it('ignores an invalid legacy value', () => {
    localStorage.setItem('old', '"five"')
    const { result } = renderHook(() => useStoredState('new', schema, 1, 'old'))
    expect(result.current[0]).toBe(1)
  })
})

describe('writeStored', () => {
  it('stores JSON that useStoredState reads back', () => {
    writeStored('k', ['vendor'])
    const { result } = renderHook(() => useStoredState('k', z.array(z.string()), []))
    expect(result.current[0]).toEqual(['vendor'])
  })
})
