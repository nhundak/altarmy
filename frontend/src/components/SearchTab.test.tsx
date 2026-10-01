import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { robeResult } from '../test/results'
import { characters, status, withEnchanter } from '../test/status'
import { GUEST, mockApi, renderWithProviders } from '../test/utils'
import { SearchTab, SHOW_ARCANE_SALVAGER } from './SearchTab'
import { SYNC_DOWNLOAD } from './SyncCard'

// Tests that only check paging swap the results table for one line per row: rendering 150 full rows
// in jsdom takes seconds on a loaded machine.
const table = vi.hoisted(() => ({ stub: false }))
vi.mock('./ResultsTable', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./ResultsTable')>()
  return {
    ...actual,
    ResultsTable: (props: Parameters<typeof actual.ResultsTable>[0]) =>
      table.stub ? <div>{props.results.length} rows</div> : <actual.ResultsTable {...props} />,
  }
})
afterEach(() => {
  table.stub = false
})

const noResults = { results: [], total: 0, items: {}, classes: {} }

const house = (realm: string, faction: string, prices = 10) => ({
  auction_house_id: 1,
  realm,
  faction,
  prices,
  last_scan: '2026-09-24 10:00:00',
  last_scan_items: prices,
  scans_7d: 1,
  uploaders_7d: 1,
})

function urls(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([request]) => new URL(request.url)).filter((u) => u.pathname === pathname)
}

/** Seed the stored setup for both test sessions; most tests make gold, selling anything. */
const withSetup = (setup: object | null) => {
  for (const uid of ['g1', 'guest']) {
    if (setup) localStorage.setItem(`altarmy-profit.setup.${uid}`, JSON.stringify(setup))
    else localStorage.removeItem(`altarmy-profit.setup.${uid}`)
  }
}
const GOLD = { aim: 'gold', selling: 'any' }

/** The buttons of the question named `name`, by label. */
const answers = (name: string) =>
  within(screen.getByRole('group', { name })).getAllByRole('button').map((b) => b.getAttribute('aria-label'))

describe('SearchTab', () => {
  const realm = () => screen.getByRole('combobox', { name: 'Realm' })

  beforeEach(() => withSetup(GOLD))

  it('says so when no game data is loaded', async () => {
    mockApi({ '/api/status': status({ recipes: 0 }), '/api/characters': characters })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/No game data has been loaded yet/)).toBeInTheDocument()
  })

  it('browses every recipe of a realm without characters', async () => {
    const shared = { realm: 'Classic Beta PvE', faction: '' }
    const fetch = mockApi({
      '/api/status': status({ characters: 0, selection: shared }),
      '/api/characters': { groups: [], selection: shared },
      '/api/coverage': [house('Classic Beta PvE', ''), house('Dreamscythe', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/Browsing every recipe on this realm/)).toBeInTheDocument()
    expect(screen.queryByRole('radiogroup', { name: 'Recipes' })).not.toBeInTheDocument()
    expect(await screen.findByText('No recipes match these filters with the current prices.')).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toHaveLength(1)
    await waitFor(() =>
      expect(screen.getByRole('combobox', { name: 'Realm' })).toHaveValue('Classic Beta PvE (both factions)'),
    )
  })

  it('shows how fresh the selected auction house prices are', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', ''), { ...house('Dreamscythe', 'Horde'), auction_house_id: 2 }],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />, GUEST)
    const freshness = await screen.findByRole('status', { name: 'Price freshness' })
    expect(freshness).toHaveTextContent(/Auction house prices are from a scan \d+ days ago\./)
  })

  it('uploads a scan right in the realm card', async () => {
    const appended = new Map<string, unknown>()
    vi.stubGlobal(
      'FormData',
      class extends FormData {
        override append(name: string, value: string | Blob, fileName?: string): void {
          appended.set(name, value)
          super.append(name, typeof value === 'string' ? value : `file ${fileName}`)
        }
      },
    )
    const imported = { kind: 'altarmy', detail: '', characters: 1, groups: [], realms: [] }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
      '/api/uploads': imported,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    await userEvent.click(await within(card).findByRole('button', { name: 'Upload your scan' }))
    expect(within(card).getByRole('heading', { name: 'Upload your scan' })).toBeInTheDocument()
    expect(within(card).queryByRole('combobox', { name: 'Realm' })).not.toBeInTheDocument()
    expect(within(card).getByRole('button', { name: 'Auto-upload' })).toBeInTheDocument()
    const file = new File(['AltArmyTBC_Data = {}'], 'AltArmy_TBC.lua')
    await userEvent.upload(card.querySelector<HTMLInputElement>('input[type="file"]')!, file)
    await userEvent.click(within(card).getByRole('button', { name: 'Upload' }))
    expect(await within(card).findByText(/Uploaded 1 characters/)).toBeInTheDocument()
    const post = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'POST')
    expect(new URL(post!.url).pathname).toBe('/api/uploads')
    expect(appended.get('file')).toBe(file)
    // The Alt Army Sync mention opens the same steps as the Auto-upload card.
    await userEvent.click(within(card).getByRole('button', { name: 'Alt Army Sync' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(within(card).getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(within(card).getByRole('button', { name: 'Continue' }))
    expect(await within(card).findByRole('combobox', { name: 'Realm' })).toBeInTheDocument()
    vi.unstubAllGlobals()
  })

  it("opens Alt Army Sync's steps from the realm card's Auto-upload button", async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    await userEvent.click(await within(card).findByRole('button', { name: 'Auto-upload' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(within(card).getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(within(card).getByRole('button', { name: 'Back to the realm' }))
    expect(await within(card).findByRole('combobox', { name: 'Realm' })).toBeInTheDocument()
  })

  it("opens Alt Army Sync's steps from the upload's Auto-upload card", async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    await userEvent.click(await within(card).findByRole('button', { name: 'Upload your scan' }))
    await userEvent.click(within(card).getByRole('button', { name: 'Auto-upload' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    // The manual upload is now the card beside it.
    await userEvent.click(within(card).getByRole('button', { name: 'Upload your scan' }))
    expect(await within(card).findByRole('heading', { name: 'Upload your scan' })).toBeInTheDocument()
  })

  it('points hosted users to the Upload page for prices, with nothing to rank until a realm has them', async () => {
    const fetch = mockApi({
      '/api/status': status({ characters: 0, selection: null, prices: 0 }),
      '/api/characters': { groups: [], selection: null },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />, GUEST)
    expect(await screen.findByText(/No prices yet for this realm\. At the auction house, press Alt Army scan/)).toBeInTheDocument()
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    expect(realm()).toHaveValue('')
    expect(screen.queryByRole('button', { name: 'Advanced Filters' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('asks what the user is after, then how to sell, then ranks per hour', async () => {
    withSetup(null)
    localStorage.setItem('altarmy-profit.search.unlearned', '"soon"')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await screen.findByRole('group', { name: 'What are you after?' })
    expect(screen.getByRole('heading', { name: 'What are you after?' })).toBeInTheDocument()
    expect(answers('What are you after?')).toEqual(['Make gold', 'Skill up'])
    expect(screen.queryByRole('combobox', { name: 'Realm' })).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Make gold' }))
    await screen.findByRole('group', { name: 'How do you want to sell?' })
    expect(answers('How do you want to sell?')).toEqual(['Only what reliably sells', 'Anything that might sell'])
    // the answer so far leads back to its question
    expect(screen.getByRole('button', { name: 'Making gold' })).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])

    await userEvent.click(screen.getByRole('button', { name: 'Anything that might sell' }))
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.get('sort')).toBe('rate')
    expect(rank?.searchParams.get('unlearned')).toBe('none') // only recipes they know
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(rank?.searchParams.has('professions')).toBe(false)
    expect(JSON.parse(localStorage.getItem('altarmy-profit.setup.g1') ?? '')).toEqual({ aim: 'gold', selling: 'any' })
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    expect(within(summary).getAllByRole('button').map((b) => b.textContent)).toEqual([
      'Making gold',
      'Anything that might sell',
    ])
    expect(realm()).toBeInTheDocument()
    expect(screen.queryByText('Rank by')).not.toBeInTheDocument()
  })

  it('sells reliably through vendors and disenchanting only', async () => {
    withSetup({ aim: 'gold' })
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Only what reliably sells' }))
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant'])
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    expect(within(summary).getByRole('button', { name: 'Only what reliably sells' })).toBeInTheDocument()
  })

  it('skills up one profession without trivial recipes, losing ones included, until the filters say otherwise', async () => {
    withSetup(null)
    localStorage.setItem('altarmy-profit.search.minProfit', JSON.stringify(0.5))
    localStorage.setItem('altarmy-profit.search.minRoi', JSON.stringify(0))
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Skill up' }))
    await screen.findByRole('group', { name: 'Which profession?' })
    expect(answers('Which profession?')).toEqual(['Any profession', 'Cooking', 'Tailoring'])
    const tailoring = screen.getByRole('button', { name: 'Tailoring' })
    const tailor = within(tailoring).getByText('Tailor Guy')
    expect(tailor).toHaveAttribute('data-class', 'MAGE')
    expect(tailor.parentElement).toHaveTextContent(/^Tailor Guy 50\/75$/)
    expect(urls(fetch, '/api/rank')).toEqual([])
    await userEvent.click(screen.getByRole('button', { name: 'Tailoring' }))
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.get('include_trivial')).toBe('false')
    expect(rank?.searchParams.has('min_profit')).toBe(false)
    expect(rank?.searchParams.has('min_roi')).toBe(false) // losses have a negative ROI
    expect(rank?.searchParams.get('sort')).toBe('skill')
    expect(rank?.searchParams.get('unlearned')).toBe('now') // and those they can train now
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant']) // no auction house
    expect(screen.getByRole('radio', { name: 'Include recipes I can train now' })).toBeChecked()
    expect(rank?.searchParams.getAll('professions')).toEqual(['Tailoring'])
    expect(rank?.searchParams.getAll('skill_crafters')).toEqual(['Tailor Guy']) // the only tailor, picked at once
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
    expect(localStorage.getItem('altarmy-profit.search.minProfit')).toBe('null')
    expect(localStorage.getItem('altarmy-profit.search.minRoi')).toBe('null')
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    expect(within(summary).getAllByRole('button').map((b) => b.textContent)).toEqual(['Skilling up', 'Tailoring'])

    const skillUps = screen.getByRole('checkbox', { name: 'Show only recipes that can give a skill up' })
    expect(skillUps).toBeChecked()
    await userEvent.click(skillUps)
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('include_trivial')).toBe('true'))
  })

  it('asks which of several tailors are skilling up before searching', async () => {
    withSetup({ aim: 'skill' })
    const [first, ...rest] = characters.groups
    const seamstress = {
      name: 'Seamstress',
      class_file: 'PRIEST',
      level: 20,
      professions: [{ name: 'Tailoring', rank: 30, max_rank: 75, recipes: 1 }],
      talents: [],
      vendor_discounts: [],
    }
    const tailors = { ...characters, groups: [{ ...first!, characters: [...first!.characters, seamstress] }, ...rest] }
    const fetch = mockApi({ '/api/status': status(), '/api/characters': tailors, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Tailoring' }))
    const who = screen.getByRole('group', { name: 'Who is skilling up?' })
    const guy = within(who).getByRole('checkbox', { name: /Tailor Guy 50\/75/ })
    const sea = within(who).getByRole('checkbox', { name: /Seamstress 30\/75/ })
    expect(guy).toBeChecked()
    expect(sea).toBeChecked()
    const done = screen.getByRole('button', { name: 'Done' })
    await userEvent.click(guy)
    await userEvent.click(sea)
    expect(done).toBeDisabled()
    expect(urls(fetch, '/api/rank')).toEqual([])
    await userEvent.click(sea)
    await userEvent.click(done)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    expect(urls(fetch, '/api/rank')[0]?.searchParams.getAll('skill_crafters')).toEqual(['Seamstress'])
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    await userEvent.click(within(summary).getByRole('button', { name: 'Tailoring (Seamstress)' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Tailoring' }))
    expect(screen.getByRole('checkbox', { name: /Seamstress/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Tailor Guy/ })).not.toBeChecked()
  })

  it('asks for the profession again when the characters picked for it are gone', async () => {
    withSetup({ aim: 'skill', profession: 'Tailoring', characters: ['Retired'] })
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('group', { name: 'Which profession?' })).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('offers only professions that have recipes', async () => {
    withSetup({ aim: 'skill' })
    const fishers = {
      ...characters,
      groups: [
        {
          ...characters.groups[0]!,
          characters: [
            {
              ...characters.groups[0]!.characters[0]!,
              professions: [
                { name: 'Fishing', rank: 10, max_rank: 75, recipes: 0 },
                { name: 'Tailoring', rank: 50, max_rank: 75, recipes: 1 },
              ],
            },
          ],
        },
      ],
    }
    mockApi({
      '/api/status': status(),
      '/api/characters': fishers,
      '/api/professions': ['Cooking', 'Tailoring'],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(answers('Which profession?')).toEqual(['Any profession', 'Tailoring']))
  })

  it('skills up any profession: every recipe that gives someone a skill point', async () => {
    withSetup({ aim: 'skill' })
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    const any = await screen.findByRole('button', { name: 'Any profession' })
    expect(within(any).queryByText('Tailor Guy')).not.toBeInTheDocument()
    await userEvent.click(any)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.has('professions')).toBe(false)
    expect(rank?.searchParams.get('sort')).toBe('skill')
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    expect(within(summary).getAllByRole('button').map((b) => b.textContent)).toEqual(['Skilling up', 'Any profession'])
  })

  it("can't skill up without characters, saying why", async () => {
    withSetup({ aim: 'skill', profession: 'Tailoring' })
    mockApi({
      '/api/status': status({ characters: 0 }),
      '/api/characters': { groups: [], selection: null },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const aims = await screen.findByRole('group', { name: 'What are you after?' })
    expect(within(aims).getByRole('button', { name: 'Skill up' })).toBeDisabled()
    expect(within(aims).getByText(/Upload your characters first/)).toBeInTheDocument()
    expect(within(aims).getByRole('button', { name: 'Make gold' })).toBeEnabled()
  })

  it('reopens one question from the summary, hiding the search meanwhile', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    await userEvent.click(screen.getByRole('button', { name: 'Anything that might sell' }))
    await screen.findByRole('group', { name: 'How do you want to sell?' })
    expect(screen.getByRole('button', { name: 'Anything that might sell' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.queryByRole('combobox', { name: 'Realm' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Only what reliably sells' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant']))
    expect(await screen.findByRole('button', { name: 'Only what reliably sells' })).toBeInTheDocument()

    // changing what the user is after asks what the new aim needs
    await userEvent.click(screen.getByRole('button', { name: 'Making gold' }))
    await screen.findByRole('group', { name: 'What are you after?' })
    expect(screen.getByRole('button', { name: 'Make gold' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: 'Skill up' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Cooking' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('sort')).toBe('skill'))
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Cooking'])
  })

  it('asks the follow-up question again whenever the aim is picked', async () => {
    withSetup({ aim: 'skill', profession: 'Cooking', selling: 'reliable' })
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))

    // picking skill up again, with a profession already chosen, still asks which one
    await userEvent.click(await screen.findByRole('button', { name: 'Skilling up' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Skill up' }))
    await screen.findByRole('group', { name: 'Which profession?' })
    expect(screen.getByRole('button', { name: 'Cooking' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: 'Tailoring' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Tailoring']))

    // likewise making gold asks again how to sell, the answer kept from before marked
    await userEvent.click(await screen.findByRole('button', { name: 'Skilling up' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Make gold' }))
    await screen.findByRole('group', { name: 'How do you want to sell?' })
    expect(screen.getByRole('button', { name: 'Only what reliably sells' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: 'Anything that might sell' }))
    await waitFor(() =>
      expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah']),
    )
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('sort')).toBe('rate')
  })

  it('asks for the profession again on a realm where nobody has it, with the realm picker at hand', async () => {
    withSetup({ aim: 'skill', profession: 'Tailoring' })
    let selection = { realm: 'Classic Beta PvE', faction: 'Horde' }
    const fetch = mockApi({
      '/api/status': () => status({ selection }),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/selection': async (_: URL, request: Request) => {
        selection = (await request.json()) as typeof selection
        return status({ selection })
      },
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Tailoring']))
    await userEvent.click(realm())
    await userEvent.click(await screen.findByRole('option', { name: 'Dreamscythe (Horde) · 2 characters' }))
    expect(await screen.findByText(/None of your characters on this realm has a profession yet/)).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Which profession?' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Advanced Filters' })).not.toBeInTheDocument()
    await userEvent.click(realm())
    await userEvent.click(await screen.findByRole('option', { name: 'Classic Beta PvE (Horde) · 1 character' }))
    expect(await screen.findByRole('group', { name: 'Your setup' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Advanced Filters' })).toBeInTheDocument()
  })

  it('opens at the profession question when the saved one is on nobody', async () => {
    withSetup({ aim: 'skill', profession: 'Alchemy' })
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('group', { name: 'Which profession?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Skilling up' })).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('suggests Enchanting when nobody on the realm can disenchant', async () => {
    withSetup({ aim: 'gold', selling: 'reliable' })
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<SearchTab />)
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/None of your characters on Classic Beta PvE has Enchanting/)
    expect(alert).toHaveTextContent(/Levelling Enchanting on any alt is an easy way to expand your options/)
    expect(alert).toHaveTextContent(/Until then only vendor sales count/)
    expect(screen.getByRole('checkbox', { name: 'Disenchant' })).toHaveAccessibleDescription(
      /None of your characters here has Enchanting, so nothing can be disenchanted\.$/,
    )
    unmount()

    withSetup(GOLD)
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('alert')).not.toHaveTextContent(/only vendor sales/)
  })

  it('says nothing about Enchanting with an enchanter, or when browsing', async () => {
    mockApi({ '/api/status': status(), '/api/characters': withEnchanter, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(screen.queryByText(/has Enchanting/)).not.toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: 'Disenchant' })).not.toHaveAccessibleDescription(/has Enchanting/)
    unmount()

    const shared = { realm: 'Classic Beta PvE', faction: '' }
    mockApi({
      '/api/status': status({ characters: 0, selection: shared }),
      '/api/characters': { groups: [], selection: shared },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/Browsing every recipe on this realm/)
    expect(screen.queryByText(/has Enchanting/)).not.toBeInTheDocument()
  })

  it('ranks with the stored parameters', async () => {
    localStorage.setItem('altarmy-profit.search.unlearned', '"soon"')
    localStorage.setItem('altarmy-profit.search.includeTrivial', 'false')
    localStorage.setItem('altarmy-profit.search.open', JSON.stringify(['advanced', 'characters']))
    localStorage.setItem('altarmy-profit.search.exits', JSON.stringify(['ah', 'vendor']))
    localStorage.setItem('altarmy-profit.search.minCost', JSON.stringify(0.5))
    localStorage.setItem('altarmy-profit.search.maxCost', JSON.stringify(20))
    localStorage.setItem('altarmy-profit.search.minRoi', 'null')
    localStorage.setItem('altarmy-profit.search.maxRoi', JSON.stringify(250))
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByLabelText('Min cost (gold)')).toHaveValue('0.5')
    expect(screen.getByLabelText('Max cost (gold)')).toHaveValue('20')
    expect(screen.getByLabelText('Min profit (gold)')).toHaveValue('0.0001')
    expect(screen.getByLabelText('Min ROI (%)')).toHaveValue('')
    expect(screen.getByRole('checkbox', { name: 'Auction house' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Disenchant' })).not.toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Disenchant' })).toHaveAccessibleDescription(
      /Usually the most reliable way to turn a profit/,
    )
    expect(screen.getByRole('checkbox', { name: 'Auction house' })).toHaveAccessibleDescription(
      'Volatile, unpredictable, but potentially lucrative. You will need to take an active role in figuring out what sells reliably.',
    )
    expect(
      screen.getByText("Dead simple, 100% reliable. It's rarely profitable, but use it if you can."),
    ).toBeInTheDocument()
    expect(screen.getByRole('radio', { name: 'Include recipes I can train soon (20 skill points)' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Show only recipes that can give a skill up' })).toBeChecked()
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    expect(screen.queryByRole('button', { name: /^Characters/ })).not.toBeInTheDocument()
    await screen.findByText(/No recipes match these filters/)
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.toString()).toBe(
      'game_version=forever&unlearned=soon&include_trivial=false&exits=vendor&exits=ah&arcane_salvager=false&min_cost=5000&max_cost=200000&min_profit=1&max_roi=2.5&sort=rate&top=50&price_version=0',
    )
  })

  it('hides the Arcane Salvager checkbox and never counts on one while it is hidden', async () => {
    if (SHOW_ARCANE_SALVAGER) return
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': { ...characters, arcane_salvager: true },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(screen.queryByRole('checkbox', { name: 'Use Arcane Salvager for disenchanting' })).toBeNull()
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('arcane_salvager')).toBe('false')
  })

  it.skipIf(!SHOW_ARCANE_SALVAGER)('disenchants at an Arcane Salvager when a character can make one, until the user says otherwise', async () => {
    const salvager = () => urls(fetch, '/api/rank').at(-1)?.searchParams.get('arcane_salvager')
    let fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<SearchTab />)
    const box = () => screen.getByRole('checkbox', { name: 'Use Arcane Salvager for disenchanting' })
    await screen.findByText(/No recipes match these filters/)
    expect(box()).not.toBeChecked()
    expect(salvager()).toBe('false')
    unmount()

    fetch = mockApi({
      '/api/status': status(),
      '/api/characters': { ...characters, arcane_salvager: true },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(box()).toBeChecked()
    expect(box()).toHaveAccessibleDescription("10% chance of extra disenchanting materials. Usable only at campfires.")
    expect(salvager()).toBe('true')
    expect(urls(fetch, '/api/rank')).toHaveLength(1)
    await userEvent.click(box())
    await waitFor(() => expect(salvager()).toBe('false'))
    expect(localStorage.getItem('altarmy-profit.search.arcaneSalvager')).toBe('false')
  })

  it('saves the time settings on the server, then ranks again', async () => {
    const config = {
      ah_search: 8, ah_buy: 4, ah_post: 6, vendor_buy: 2, vendor_sell: 1.5, mail_send: 8, mail_attach: 2,
      mail_open: 3, mail_attachments: 12, switch_character: 45, disenchant: 3.5, craft_overhead: 0.5, batch: 10,
      time_value: 0, run_speed: 7, detour: 1.3,
    }
    const city = (name: string, faction: string) => ({ name, faction, hub: 'Auctioneer', locations: 9, vendors: 3 })
    const settings = {
      cities: [city('Orgrimmar', 'Horde'), city('Thunder Bluff', 'Horde')],
      city: null,
      active: null,
      config,
      defaults: config,
    }
    // The server answers with what it stored.
    const saved: object[] = []
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/time': async (_: URL, request: Request) => {
        if (request.method !== 'PUT') return settings
        const body = (await request.json()) as { city: string | null; config: object }
        saved.push(body)
        return { ...settings, city: body.city, config: { ...config, ...body.config } }
      },
    })
    renderWithProviders(<SearchTab />)
    // Crafts per session is one of the search's options; the rest are under Time assumptions.
    const batch = await screen.findByLabelText('Crafts per session')
    expect(screen.getByRole('button', { name: 'Time assumptions' })).toHaveAttribute('aria-expanded', 'false')
    const ranked = urls(fetch, '/api/rank').length
    fireEvent.change(batch, { target: { value: '5' } })
    await waitFor(() => expect(saved).toEqual([{ city: null, config: { batch: 5 } }]), { timeout: 3000 })
    await waitFor(() => expect(urls(fetch, '/api/rank').length).toBeGreaterThan(ranked))

    // A change under Time assumptions keeps the new batch (each editor saves the settings as they now are).
    await userEvent.click(screen.getByRole('button', { name: 'Time assumptions' }))
    expect(screen.getByRole('combobox', { name: 'Craft Location' })).toHaveValue('Wherever pays best')
    for (const gone of ['An hour of your time is worth (gold)', 'Stacks per mail', 'Disenchant (per item)', /Detour/]) {
      expect(screen.queryByLabelText(gone)).not.toBeInTheDocument()
    }
    fireEvent.change(screen.getByLabelText('Open a mail'), { target: { value: '4' } })
    await waitFor(() => expect(saved).toHaveLength(2), { timeout: 3000 })
    expect(saved[1]).toEqual({ city: null, config: { batch: 5, mail_open: 4 } })
    expect(batch).toHaveValue('5')
  })

  it('folds the options into a closed Filters section on small screens', async () => {
    const real = window.matchMedia
    // Only the query for "narrower than sm" matches.
    window.matchMedia = (query: string) => ({ ...real(query), matches: query.startsWith('not all') })
    try {
      mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
      renderWithProviders(<SearchTab />)
      const filters = await screen.findByRole('button', { name: 'Filters' })
      expect(filters).toHaveAttribute('aria-expanded', 'false')
      expect(screen.getByRole('checkbox', { name: 'Vendor', hidden: true })).not.toBeVisible()
      await userEvent.click(filters)
      expect(filters).toHaveAttribute('aria-expanded', 'true')
      expect(screen.getByRole('checkbox', { name: 'Vendor' })).toBeVisible()
      expect(screen.getByRole('radio', { name: 'Show recipes I already know' })).toBeVisible()
    } finally {
      window.matchMedia = real
    }
  })

  it('opens the Filters section on large screens, and it folds', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('checkbox', { name: 'Vendor' })).toBeVisible()
    const filters = screen.getByRole('button', { name: 'Filters' })
    expect(filters).toHaveAttribute('aria-expanded', 'true')
    await userEvent.click(filters)
    expect(filters).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('checkbox', { name: 'Vendor', hidden: true })).not.toBeVisible()
  })

  it('opens and closes Advanced Filters, remembering it, and ignores sections that are gone', async () => {
    localStorage.setItem('altarmy-profit.search.open', JSON.stringify(['characters']))
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    const advanced = await screen.findByRole('button', { name: 'Advanced Filters' })
    expect(advanced).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(advanced)
    expect(advanced).toHaveAttribute('aria-expanded', 'true')
    expect(localStorage.getItem('altarmy-profit.search.open')).toBe('["advanced"]')
    await userEvent.click(advanced)
    expect(localStorage.getItem('altarmy-profit.search.open')).toBe('[]')
  })

  it('asks for a way to sell instead of ranking when none is ticked', async () => {
    localStorage.setItem('altarmy-profit.search.exits', '[]')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/Pick at least one way to sell/)).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('shows 50 more results at a time', { timeout: 15_000 }, async () => {
    table.stub = true
    // As many results as asked for, out of 120.
    const rank = (url: URL) => {
      const top = Math.min(Number(url.searchParams.get('top')), 120)
      const results = Array.from({ length: top }, (_, i) => ({ ...robeResult, recipe_id: i }))
      return { results, total: 120, items: {}, classes: {} }
    }
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': rank })
    renderWithProviders(<SearchTab />)
    const slow = { timeout: 5000 }
    expect(await screen.findByText('Showing 50 of 120', {}, slow)).toBeInTheDocument()
    expect(screen.getByText('50 rows')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show more' }))
    expect(await screen.findByText('Showing 100 of 120', {}, slow)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show more' }))
    await waitFor(
      () => expect(screen.queryByRole('button', { name: 'Show more' })).not.toBeInTheDocument(),
      slow,
    )
    expect(screen.getByText('120 rows')).toBeInTheDocument()
    expect(urls(fetch, '/api/rank').map((u) => u.searchParams.get('top'))).toEqual(['50', '100', '150'])
  })

  it('switches realm on the server', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/selection': status({ selection: { realm: 'Dreamscythe', faction: 'Horde' } }),
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    await userEvent.click(realm())
    await userEvent.click(await screen.findByRole('option', { name: 'Dreamscythe (Horde) · 2 characters' }))
    await waitFor(() => expect(urls(fetch, '/api/selection')).toHaveLength(1))
    const put = fetch.mock.calls.map(([r]) => r).find((r) => new URL(r.url).pathname === '/api/selection')
    expect(put?.method).toBe('PUT')
    expect(await put?.json()).toEqual({ realm: 'Dreamscythe', faction: 'Horde' })
    await waitFor(() => expect(realm()).toHaveValue('Dreamscythe (Horde) · 2 characters'))
  })

  it('switches to a realm with prices but no characters', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', ''), house('Atiesh', '')],
      '/api/rank': noResults,
      '/api/selection': status({ selection: { realm: 'Atiesh', faction: '' } }),
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    await userEvent.click(realm())
    expect(screen.queryByRole('option', { name: 'Classic Beta PvE (both factions)' })).not.toBeInTheDocument()
    await userEvent.click(await screen.findByRole('option', { name: 'Atiesh (both factions)' }))
    await waitFor(() => expect(urls(fetch, '/api/selection')).toHaveLength(1))
    const put = fetch.mock.calls.map(([r]) => r).find((r) => new URL(r.url).pathname === '/api/selection')
    expect(await put?.json()).toEqual({ realm: 'Atiesh', faction: '' })
  })

  it('saves changed parameters and ignores malformed stored values', async () => {
    localStorage.setItem('altarmy-profit.search.unlearned', '"yes"')
    localStorage.setItem('altarmy-profit.search.maxProfit', 'garbage')
    localStorage.setItem('altarmy-profit.search.exits', '["trade"]')
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    const maxProfit = await screen.findByLabelText('Max profit (gold)')
    expect(maxProfit).toHaveValue('')
    for (const name of ['Vendor', 'Disenchant', 'Auction house']) {
      expect(screen.getByRole('checkbox', { name })).toBeChecked()
    }
    expect(screen.getByRole('radio', { name: 'Show recipes I already know' })).toBeChecked()
    const skillUps = screen.getByRole('checkbox', { name: 'Show only recipes that can give a skill up' })
    expect(skillUps).not.toBeChecked()
    fireEvent.change(maxProfit, { target: { value: '40' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('40')
    fireEvent.change(maxProfit, { target: { value: '' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('null')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disenchant' }))
    expect(localStorage.getItem('altarmy-profit.search.exits')).toBe('["vendor","ah"]')
    fireEvent.click(screen.getByRole('radio', { name: 'Include all recipes' }))
    expect(localStorage.getItem('altarmy-profit.search.unlearned')).toBe('"all"')
    fireEvent.click(skillUps)
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
  })
})
