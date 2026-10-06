import { describe, expect, it } from 'vitest'
import type { CharacterGroup } from '../api/client'
import { filterSkills, presetsFor, professionsOf, searchKey, skillsByCharacter, storePresets } from './setup'

describe('professionsOf', () => {
  it('leaves out Mining and Skinning', () => {
    const profession = (name: string) => ({ name, rank: 1, max_rank: 75, recipes: 1 })
    const group = {
      realm: 'R',
      faction: 'Horde',
      characters: [
        {
          name: 'Amy',
          class_file: 'MAGE',
          level: 22,
          professions: [profession('Mining'), profession('Skinning'), profession('Tailoring')],
          talents: [],
          vendor_discounts: [],
        },
      ],
    }
    expect(professionsOf(group as CharacterGroup).map((p) => p.name)).toEqual(['Tailoring'])
  })
})

describe('skillsByCharacter', () => {
  it('groups the professions by character, both alphabetically', () => {
    const holder = (name: string, rank: number) => ({ name, classFile: 'MAGE', level: 22, rank, maxRank: 75 })
    const characters = skillsByCharacter([
      { name: 'Tailoring', holders: [holder('Zed', 10), holder('Amy', 20)] },
      { name: 'Cooking', holders: [holder('Zed', 30)] },
    ])
    expect(characters.map((c) => c.name)).toEqual(['Amy', 'Zed'])
    expect(characters[1]?.professions).toEqual([
      { name: 'Cooking', rank: 30, maxRank: 75 },
      { name: 'Tailoring', rank: 10, maxRank: 75 },
    ])
  })
})

describe('filterSkills', () => {
  const characters = [
    { name: 'Amy', classFile: 'MAGE', level: 22, professions: [{ name: 'Cooking', rank: 1, maxRank: 75 }] },
    {
      name: 'Frell',
      classFile: 'ROGUE',
      level: 60,
      professions: [
        { name: 'Cooking', rank: 1, maxRank: 75 },
        { name: 'Tailoring', rank: 1, maxRank: 75 },
      ],
    },
  ]
  const shown = (query: string) =>
    filterSkills(characters, query).map((c) => `${c.name}: ${c.professions.map((p) => p.name).join(', ')}`)

  it('keeps every profession of a character whose name matches', () => {
    expect(shown('frel')).toEqual(['Frell: Cooking, Tailoring'])
  })

  it('keeps only the matching professions, and drops characters with none', () => {
    expect(shown('TAIL')).toEqual(['Frell: Tailoring'])
    expect(shown(' cook ')).toEqual(['Amy: Cooking', 'Frell: Cooking'])
    expect(shown('zzz')).toEqual([])
  })

  it('keeps everything without a query', () => {
    expect(shown('')).toEqual(['Amy: Cooking', 'Frell: Cooking, Tailoring'])
  })
})

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
