import { describe, expect, it } from 'vitest'
import { presetsFor, searchKey, storePresets } from './setup'

describe('storePresets', () => {
  it("writes an answer's presets under its aim's keys only", () => {
    storePresets('skill', presetsFor({ aim: 'skill' }, 'aim'))
    expect(localStorage.getItem(searchKey('skill', 'exits'))).toBe('["vendor","disenchant","keep"]')
    expect(localStorage.getItem(searchKey('skill', 'minProfit'))).toBe('null')
    expect(localStorage.getItem(searchKey('gold', 'exits'))).toBeNull()
    storePresets('gold', presetsFor({ aim: 'gold' }, 'aim'))
    expect(localStorage.getItem(searchKey('gold', 'exits'))).toBe('["vendor","disenchant","ah"]')
    expect(localStorage.getItem(searchKey('gold', 'minProfit'))).toBe('0.0001') // making gold sells every way
    expect(localStorage.getItem(searchKey('skill', 'exits'))).toBe('["vendor","disenchant","keep"]')
  })
})
