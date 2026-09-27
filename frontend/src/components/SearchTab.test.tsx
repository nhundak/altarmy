import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { robeResult } from '../test/results'
import { characters, status } from '../test/status'
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
  sources: ['auctionator'],
})

function urls(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([request]) => new URL(request.url)).filter((u) => u.pathname === pathname)
}

/** Seed the stored goal for both test sessions; most tests search for profit per craft (no `sort` sent). */
const withGoal = (goal: string | null) => {
  for (const uid of ['g1', 'guest']) {
    if (goal) localStorage.setItem(`altarmy-profit.goal.${uid}`, JSON.stringify(goal))
    else localStorage.removeItem(`altarmy-profit.goal.${uid}`)
  }
}

describe('SearchTab', () => {
  const realm = () => screen.getByRole('combobox', { name: 'Realm and faction' })

  beforeEach(() => withGoal('budget'))

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
    expect(screen.queryByRole('switch', { name: /Include recipes not learned yet/ })).not.toBeInTheDocument()
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
    expect(await screen.findByText(/then upload Auctionator.lua on the Upload page/)).toBeInTheDocument()
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    expect(realm()).toHaveValue('')
    expect(screen.queryByRole('button', { name: 'Advanced Filters' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('asks for a goal first, then ranks the way it wants', async () => {
    withGoal(null)
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    const goals = await screen.findByRole('group', { name: 'Your goal' })
    expect(screen.getByRole('heading', { name: 'What is your goal?' })).toBeInTheDocument()
    expect(within(goals).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
      'Maximize profit',
      'Make profit on a budget',
      'Skill up for minimum expense',
    ])
    expect(screen.queryByRole('combobox', { name: 'Realm and faction' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])

    await userEvent.click(within(goals).getByRole('button', { name: 'Maximize profit' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('sort')).toBe('rate'))
    expect(localStorage.getItem('altarmy-profit.goal.g1')).toBe('"profit"')
    await waitFor(() => expect(screen.queryByRole('group', { name: 'Your goal' })).not.toBeInTheDocument())
    expect(screen.getByText('Goal: Maximize profit.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Change goal' })).toBeInTheDocument()
    expect(realm()).toBeInTheDocument()
    // the goal ranks: no Rank by switch and no profession filter
    expect(screen.queryByText('Rank by')).not.toBeInTheDocument()
    expect(screen.queryByRole('combobox', { name: 'Professions' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.has('professions')).toBe(false)
  })

  it('skills up without trivial recipes, losing ones included, until the filters say otherwise', async () => {
    withGoal(null)
    localStorage.setItem('altarmy-profit.search.minProfit', JSON.stringify(0.5))
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Skill up for minimum expense' }))
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.get('include_trivial')).toBe('false')
    expect(rank?.searchParams.has('min_profit')).toBe(false)
    expect(rank?.searchParams.has('sort')).toBe(false)
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
    expect(localStorage.getItem('altarmy-profit.search.minProfit')).toBe('null')

    await userEvent.click(screen.getByRole('button', { name: 'Advanced Filters' }))
    await userEvent.click(screen.getByRole('checkbox', { name: /Include Trivial Recipes/ }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('include_trivial')).toBe('true'))
  })

  it('changes the goal from its row, hiding the search meanwhile', async () => {
    withGoal('profit')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('sort')).toBe('rate'))
    await userEvent.click(screen.getByRole('button', { name: 'Change goal' }))
    const goals = await screen.findByRole('group', { name: 'Your goal' })
    expect(within(goals).getByRole('button', { name: 'Maximize profit' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.queryByRole('combobox', { name: 'Realm and faction' })).not.toBeInTheDocument()
    const ranked = urls(fetch, '/api/rank').length
    await userEvent.click(within(goals).getByRole('button', { name: 'Make profit on a budget' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').length).toBeGreaterThan(ranked))
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.has('sort')).toBe(false)
    expect(await screen.findByText('Goal: Make profit on a budget.')).toBeInTheDocument()
  })

  it('ranks with the stored parameters', async () => {
    localStorage.setItem('altarmy-profit.search.includeUnlearned', 'true')
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
    expect(screen.getByRole('switch', { name: /Include recipes not learned yet/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Include Trivial Recipes/ })).not.toBeChecked()
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    expect(screen.queryByRole('button', { name: /^Characters/ })).not.toBeInTheDocument()
    await screen.findByText(/No recipes match these filters/)
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.toString()).toBe(
      'game_version=forever&include_unlearned=true&include_trivial=false&exits=vendor&exits=ah&min_cost=5000&max_cost=200000&min_profit=1&max_roi=2.5&top=50',
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
    localStorage.setItem('altarmy-profit.search.includeUnlearned', '"yes"')
    localStorage.setItem('altarmy-profit.search.maxProfit', 'garbage')
    localStorage.setItem('altarmy-profit.search.exits', '["trade"]')
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<SearchTab />)
    const maxProfit = await screen.findByLabelText('Max profit (gold)')
    expect(maxProfit).toHaveValue('')
    for (const name of ['Vendor', 'Disenchant', 'Auction house']) {
      expect(screen.getByRole('checkbox', { name, hidden: true })).toBeChecked()
    }
    const unlearned = screen.getByRole('switch', { name: /Include recipes not learned yet/ })
    expect(unlearned).not.toBeChecked()
    const trivial = screen.getByRole('checkbox', { name: /Include Trivial Recipes/, hidden: true })
    expect(trivial).toBeChecked()
    fireEvent.change(maxProfit, { target: { value: '40' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('40')
    fireEvent.change(maxProfit, { target: { value: '' } })
    expect(localStorage.getItem('altarmy-profit.search.maxProfit')).toBe('null')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disenchant', hidden: true }))
    expect(localStorage.getItem('altarmy-profit.search.exits')).toBe('["vendor","ah"]')
    fireEvent.click(unlearned)
    expect(localStorage.getItem('altarmy-profit.search.includeUnlearned')).toBe('true')
    fireEvent.click(trivial)
    expect(localStorage.getItem('altarmy-profit.search.includeTrivial')).toBe('false')
  })
})
