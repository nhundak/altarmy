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
        vendor_discounts: [],
      },
      { name: 'Plain', class_file: 'MAGE', level: 10, professions: [], talents: [], vendor_discounts: [] },
      {
        name: 'Envoy',
        class_file: 'SHAMAN',
        level: 5,
        professions: [],
        talents: [],
        vendor_discounts: [
          { faction: 'Orgrimmar', percent: 10 },
          { faction: 'Thunder Bluff', percent: 10 },
        ],
      },
    ],
  },
]

describe('CharacterList', () => {
  it('shows each character’s level, professions and Legacy talents in their own cells', () => {
    renderWithProviders(<CharacterList groups={groups} />)
    const text = (t: string) => screen.getByText((_, el) => el?.tagName === 'P' && shown(el) === t)
    expect(text('Chef')).toBeInTheDocument()
    expect(text('30')).toBeInTheDocument()
    expect(text('Cooking 150/150 · Master Chef 3/5, Bartering 2/2')).toBeInTheDocument()
    expect(text('Plain')).toBeInTheDocument()
    expect(text('10')).toBeInTheDocument()
  })

  it('says whose vendors a character’s reputation makes cheaper', () => {
    renderWithProviders(<CharacterList groups={groups} />)
    expect(screen.getByText('Vendors −10%: Orgrimmar, Thunder Bluff')).toBeInTheDocument()
  })

  it('lists each realm’s characters by level, highest first', () => {
    const [group] = groups
    renderWithProviders(<CharacterList groups={[{ ...group, characters: [...group.characters].reverse() }]} />)
    const names = screen.getAllByText(/^(Chef|Plain|Envoy)$/).map((el) => el.textContent)
    expect(names).toEqual(['Chef', 'Plain', 'Envoy'])
  })

  it('has no remove button', () => {
    renderWithProviders(<CharacterList groups={groups} />)
    expect(screen.queryByRole('button')).not.toBeInTheDocument()
  })
})
