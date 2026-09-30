import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { robeResult } from '../test/results'
import { characters, status, withEnchanter } from '../test/status'
import { GUEST, mockApi, renderWithProviders } from '../test/utils'
import { SearchTab } from './SearchTab'

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
  const realm = () => screen.getByRole('combobox', { name: 'Realm and faction' })

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
      expect(screen.getByRole('combobox', { name: 'Realm and faction' })).toHaveValue('Classic Beta PvE (both factions)'),
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
    expect(screen.getByRole('link', { name: 'Upload your scan' })).toHaveAttribute('href', '/upload')
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
    expect(screen.queryByRole('combobox', { name: 'Realm and faction' })).not.toBeInTheDocument()

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
      'anything that might sell',
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
    expect(within(summary).getByRole('button', { name: 'only what reliably sells' })).toBeInTheDocument()
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
    expect(rank?.searchParams.get('unlearned')).toBe('soon') // and those they can train soon
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant']) // no auction house
    expect(screen.getByRole('radio', { name: 'Include recipes I can train soon (20 skill points)' })).toBeChecked()
    expect(rank?.searchParams.getAll('professions')).toEqual(['Tailoring'])
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
    expect(localStorage.getItem('altarmy-profit.search.minProfit')).toBe('null')
    expect(localStorage.getItem('altarmy-profit.search.minRoi')).toBe('null')
    const summary = await screen.findByRole('group', { name: 'Your setup' })
    expect(within(summary).getAllByRole('button').map((b) => b.textContent)).toEqual(['Skilling up', 'Tailoring'])

    await userEvent.click(screen.getByRole('button', { name: 'Advanced Filters' }))
    await userEvent.click(screen.getByRole('checkbox', { name: /Include Trivial Recipes/ }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('include_trivial')).toBe('true'))
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
    expect(within(aims).getByText(/Import your characters first/)).toBeInTheDocument()
    expect(within(aims).getByRole('button', { name: 'Make gold' })).toBeEnabled()
  })

  it('reopens one question from the summary, hiding the search meanwhile', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    await userEvent.click(screen.getByRole('button', { name: 'anything that might sell' }))
    await screen.findByRole('group', { name: 'How do you want to sell?' })
    expect(screen.getByRole('button', { name: 'Anything that might sell' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.queryByRole('combobox', { name: 'Realm and faction' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Only what reliably sells' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant']))
    expect(await screen.findByRole('button', { name: 'only what reliably sells' })).toBeInTheDocument()

    // changing what the user is after asks what the new aim needs
    await userEvent.click(screen.getByRole('button', { name: 'Making gold' }))
    await screen.findByRole('group', { name: 'What are you after?' })
    expect(screen.getByRole('button', { name: 'Make gold' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: 'Skill up' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Cooking' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('sort')).toBe('skill'))
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Cooking'])
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
      /Requires at least one character with enchanting/,
    )
    expect(screen.getByText("Rarely the best profit, but it's always available.")).toBeInTheDocument()
    expect(screen.getByRole('radio', { name: 'Include recipes I can train soon (20 skill points)' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Include Trivial Recipes/ })).not.toBeChecked()
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    expect(screen.queryByRole('button', { name: /^Characters/ })).not.toBeInTheDocument()
    await screen.findByText(/No recipes match these filters/)
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.toString()).toBe(
      'game_version=forever&unlearned=soon&include_trivial=false&exits=vendor&exits=ah&min_cost=5000&max_cost=200000&min_profit=1&max_roi=2.5&sort=rate&top=50&price_version=0',
    )
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
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/time': settings,
    })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Time assumptions' }))
    const batch = await screen.findByLabelText('Crafts per session')
    expect(screen.getByRole('combobox', { name: 'Craft Location' })).toHaveValue('Whatever is fastest')
    expect(screen.getByLabelText('Open a mail')).toBeInTheDocument()
    const ranked = urls(fetch, '/api/rank').length
    fireEvent.change(batch, { target: { value: '5' } })
    for (const gone of ['An hour of your time is worth (gold)', 'Stacks per mail', 'Disenchant (per item)', /Detour/]) {
      expect(screen.queryByLabelText(gone)).not.toBeInTheDocument()
    }
    await waitFor(() => expect(fetch.mock.calls.some(([r]) => r.method === 'PUT')).toBe(true), { timeout: 3000 })
    const put = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'PUT')
    expect(await put?.json()).toEqual({ city: null, config: { batch: 5 } })
    await waitFor(() => expect(urls(fetch, '/api/rank').length).toBeGreaterThan(ranked))
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
      expect(screen.getByRole('checkbox', { name, hidden: true })).toBeChecked()
    }
    expect(screen.getByRole('radio', { name: 'Show recipes I already know' })).toBeChecked()
    const trivial = screen.getByRole('checkbox', { name: /Include Trivial Recipes/, hidden: true })
    expect(trivial).toBeChecked()
    fireEvent.change(maxProfit, { target: { value: '40' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('40')
    fireEvent.change(maxProfit, { target: { value: '' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('null')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disenchant', hidden: true }))
    expect(localStorage.getItem('altarmy-profit.search.exits')).toBe('["vendor","ah"]')
    fireEvent.click(screen.getByRole('radio', { name: 'Include all recipes' }))
    expect(localStorage.getItem('altarmy-profit.search.unlearned')).toBe('"all"')
    fireEvent.click(trivial)
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
  })
})
