import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { CharacterGroup } from '../api/client'
import { renderWithProviders, shown } from '../test/utils'
import { CharacterList } from './CharacterList'

const groups: CharacterGroup[] = [
  {
    realm: 'Classic Beta PvE',
    faction: 'Horde',
    characters: [
      {
        name: 'Chef',
        class_file: 'MAGE',
        level: 30,
        professions: [{ name: 'Cooking', rank: 150, max_rank: 150, recipes: 12 }],
        talents: [
          { spell_id: 1225457, name: 'Master Chef', rank: 3, max_rank: 5 },
          { spell_id: 1225459, name: 'Bartering', rank: 2, max_rank: 2 },
        ],
      },
      { name: 'Plain', class_file: 'MAGE', level: 10, professions: [], talents: [] },
    ],
  },
]

describe('CharacterList', () => {
  it('shows each character’s professions and Legacy talents', () => {
    renderWithProviders(<CharacterList groups={groups} />)
    const text = (t: string) => screen.getByText((_, el) => el?.tagName === 'P' && shown(el) === t)
    expect(text('Chef 30: Cooking 150/150 · Master Chef 3/5, Bartering 2/2')).toBeInTheDocument()
    expect(text('Plain 10')).toBeInTheDocument()
  })
})
