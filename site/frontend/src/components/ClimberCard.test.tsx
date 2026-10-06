import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { Selection } from '../api/client'
import type { Holder, RealmSkills } from '../lib/setup'
import { BARTERING, WORKING_OVERTIME } from '../lib/talents'
import { status } from '../test/status'
import { iconUrl, professionIcon } from '../lib/wow'
import { mockApi, renderWithProviders } from '../test/utils'
import { ClimberCard } from './ClimberCard'

const CLIMBER: Holder = { name: 'Tailor Guy', classFile: 'MAGE', level: 30, rank: 20, maxRank: 75 }
const overtime = (rank: number) => ({ spellId: WORKING_OVERTIME, name: 'Working Overtime', rank, maxRank: 5 })
const bartering = (rank: number) => ({ spellId: BARTERING, name: 'Bartering', rank, maxRank: 2 })
const HOME: Selection = { realm: 'Classic Beta PvE', faction: 'Horde' }
const AWAY: Selection = { realm: 'Dreamscythe', faction: 'Alliance' }
const character = (name: string, professions: [string, number][], level = 22) => ({
  name,
  classFile: 'MAGE',
  level,
  professions: professions.map(([p, rank]) => ({ name: p, rank, maxRank: 75 })),
})
const REALMS: RealmSkills[] = [
  {
    realm: HOME,
    label: 'Classic Beta PvE (Horde)',
    characters: [
      character('Amy', [['Cooking', 30]]),
      character('Tailor Guy', [
        ['Cooking', 5],
        ['Tailoring', 20],
      ]),
    ],
  },
  { realm: AWAY, label: 'Dreamscythe (Alliance)', characters: [character('Frell', [['Alchemy', 100]], 60)] },
]

function show(over: Partial<Parameters<typeof ClimberCard>[0]> = {}) {
  mockApi({ '/api/status': status() })
  const props = {
    realm: HOME,
    climber: CLIMBER,
    profession: 'Tailoring',
    realms: REALMS,
    importedAt: null,
    onSwitch: vi.fn(),
    onUploadAgain: vi.fn(),
    ...over,
  }
  renderWithProviders(<ClimberCard {...props} />)
  return props
}

describe('ClimberCard', () => {
  it('shows who skills up what across the card, their talents without parentheses, when uploaded and Upload again', async () => {
    const hoursAgo = new Date(Date.now() - 2 * 3_600_000).toISOString().slice(0, 19).replace('T', ' ')
    const { onUploadAgain } = show({
      climber: { ...CLIMBER, name: 'Frell Ofelements', talents: [overtime(1), bartering(2)] },
      importedAt: hoursAgo,
    })
    const card = screen.getByRole('region', { name: 'Skilling up' })
    const select = within(card).getByRole('button', { name: 'Switch character or profession' })
    expect(within(select).getByText("Frell Ofelements'")).toBeInTheDocument()
    expect(select.querySelector('img')?.getAttribute('src')).toBe(iconUrl(professionIcon('Tailoring') ?? '', 'small'))
    expect(within(card).getByText('1/5 Working Overtime, 2/2 Bartering')).toBeInTheDocument()
    expect(within(card).getByText('Updated 2 h ago')).toBeInTheDocument()
    await userEvent.click(within(card).getByRole('button', { name: 'Upload again' }))
    expect(onUploadAgain).toHaveBeenCalled()
  })

  it('leaves the talents out when the climber has none', () => {
    show()
    expect(screen.getByText("Tailor Guy's")).toBeInTheDocument()
    expect(screen.queryByText(/Working Overtime/)).not.toBeInTheDocument()
  })

  it('says what each talent does when they are hovered', async () => {
    show({ climber: { ...CLIMBER, talents: [overtime(2), bartering(1)] } })
    await userEvent.hover(screen.getByText('2/5 Working Overtime, 1/2 Bartering'))
    const tooltip = await screen.findByRole('tooltip')
    expect(within(tooltip).getByText('Working Overtime')).toBeInTheDocument()
    expect(within(tooltip).getByText('Rank 2/5')).toBeInTheDocument()
    expect(within(tooltip).getByText('Increases your chance to gain a skill increase by 8%')).toBeInTheDocument()
    expect(within(tooltip).getByText('Bartering')).toBeInTheDocument()
    expect(within(tooltip).getByText('Rank 1/2')).toBeInTheDocument()
    expect(within(tooltip).getByText('Reduces the gold price of items from all vendors by 5%')).toBeInTheDocument()
  })

  it('switches to any character\'s profession, grouped by realm and faction, then by character', async () => {
    const { onSwitch } = show()
    await userEvent.click(screen.getByRole('button', { name: 'Switch character or profession' }))
    const list = await screen.findByRole('listbox')
    const options = () => within(list).getAllByRole('option')
    const names = () => options().map((o) => o.textContent?.replace(/\d+\/\d+$/, ''))
    // each realm and faction, then each of its characters, then their professions
    expect(names()).toEqual(['Cooking', 'Cooking', 'Tailoring', 'Alchemy'])
    const home = within(list).getByText('Classic Beta PvE (Horde)')
    const away = within(list).getByText('Dreamscythe (Alliance)')
    expect(home.compareDocumentPosition(away)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
    const amy = within(list).getByRole('group', { name: 'Amy' })
    expect(within(amy).getAllByRole('option').map((o) => o.textContent?.replace(/\d+\/\d+$/, ''))).toEqual(['Cooking'])
    // each character with their level and class, only the name in its colour
    expect(within(list).getByText('Amy').parentElement).toHaveTextContent('Amy (level 22 mage)')
    expect(within(list).getByText('Amy')).toHaveAttribute('data-class', 'MAGE')
    expect(options()[2]).toHaveAttribute('aria-selected', 'true')
    // typing narrows it by realm, character or profession
    const search = screen.getByRole('textbox', { name: 'Search characters or professions' })
    await userEvent.type(search, 'cook')
    expect(names()).toEqual(['Cooking', 'Cooking'])
    await userEvent.clear(search)
    await userEvent.type(search, 'dreams')
    expect(names()).toEqual(['Alchemy'])
    await userEvent.click(options()[0]!)
    expect(onSwitch).toHaveBeenCalledWith(AWAY, 'Alchemy', 'Frell')
  })

  it('switches with the keyboard alone: arrows through the options, Enter picks, Tab closes', async () => {
    const { onSwitch } = show()
    const select = screen.getByRole('button', { name: 'Switch character or profession' })
    select.focus()
    await userEvent.keyboard(' ')
    const search = await screen.findByRole('textbox', { name: 'Search characters or professions' })
    await waitFor(() => expect(search).toHaveFocus())
    // Tab goes back to the select, closed
    await userEvent.tab()
    expect(select).toHaveFocus()
    await waitFor(() => expect(screen.queryByRole('listbox')).not.toBeInTheDocument())
    await userEvent.keyboard(' ')
    await waitFor(() => expect(search).toHaveFocus())
    // from the current one (Tailor Guy's Tailoring) the arrow goes on to Frell's Alchemy
    await waitFor(() =>
      expect(screen.getByRole('option', { name: /Tailoring/ })).toHaveAttribute('data-combobox-selected'),
    )
    await userEvent.keyboard('{ArrowDown}{Enter}')
    expect(onSwitch).toHaveBeenCalledWith(AWAY, 'Alchemy', 'Frell')
  })

  it('does nothing when the current one is picked again', async () => {
    const { onSwitch } = show()
    await userEvent.click(screen.getByRole('button', { name: 'Switch character or profession' }))
    await userEvent.click(await screen.findByRole('option', { name: /Tailoring/ }))
    expect(onSwitch).not.toHaveBeenCalled()
  })
})
