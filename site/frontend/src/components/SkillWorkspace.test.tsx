import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { focusManager } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import type { RankResult } from '../api/client'
import type { RankParams } from '../api/queries'
import { linen, robe as robeItem, thread } from '../test/items'
import { robeResult } from '../test/results'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import type { Holder } from '../lib/setup'
import { scaleRun } from '../lib/skill'
import { SkillWorkspace } from './SkillWorkspace'

const capItem = { ...robeItem, id: 4, name: 'Linen Cap', quality: 2 }
const items = { '1': linen, '2': thread, '3': robeItem, '4': capItem }
const steps = robeResult.steps.map((s) => ({ ...s, who: 'Tailor Guy' }))
// A run of 12 robes from Tailoring 20 to about 45, where a Linen Cap gives a cheaper point; 14 crafts four times
// in five.
const robeRun: RankResult = {
  ...robeResult,
  crafter: 'Tailor Guy',
  crafts: 12,
  crafts_p80: 14,
  cost: 3600,
  revenue: 0,
  profit: -3600,
  skill_ups: 12,
  stop_skill: 45,
  stop_reason: 'rival',
  overtaken_by: 'Linen Cap',
  overtaken_by_item: 4,
  // the odds of reaching 45 after 1, 2, ... crafts: 82% after 14, 95% after 20
  reach_chances: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.3, 0.5, 0.7, 0.8249, 0.86, 0.88, 0.9, 0.92, 0.94, 0.95],
  steps,
}
const capRun: RankResult = {
  ...robeRun,
  recipe_id: 101,
  recipe: 'Linen Cap',
  output_item_id: 9001, // no item info: shown by name
  output_name: 'Linen Cap',
  profit: -4800,
  cost: 4800,
}
const beltRun: RankResult = { ...robeRun, recipe_id: 102, recipe: 'Linen Belt', output_name: 'Linen Belt', profit: -100 }
const ranked = { results: [robeRun, capRun], total: 2, items, classes: {}, learn: {}, then: beltRun }

const FILTERS: Omit<RankParams, 'top'> = {
  unlearned: 'train',
  lookAhead: 0,
  sources: ['trainer', 'recipe'],
  includeTrivial: false,
  skillCrafters: ['Tailor Guy'],
  exits: ['vendor', 'keep'],
  arcaneSalvager: false,
  minCost: null,
  maxCost: null,
  minProfit: null,
  maxProfit: null,
  minRoi: null,
  maxRoi: null,
  minConfidence: null,
  professions: ['Tailoring'],
  sort: 'skill',
  runs: true,
}
const CLIMBER = { name: 'Tailor Guy', classFile: 'MAGE', rank: 20, maxRank: 75 }

function urls(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([r]) => new URL(r.url)).filter((u) => u.pathname === pathname)
}
async function bodies(fetch: ReturnType<typeof mockApi>, pathname: string) {
  const requests = fetch.mock.calls.map(([r]) => r).filter((r) => new URL(r.url).pathname === pathname)
  return Promise.all(requests.map((r) => r.clone().json() as Promise<Record<string, unknown>>))
}

function api(over: Record<string, unknown> = {}) {
  return mockApi({
    '/api/status': status({ price_version: 1 }),
    '/api/rank': ranked,
    '/api/evaluate': () => ({ result: { ...scaleRun(robeRun, 14), cost: 4200 }, items }),
    '/api/events': {},
    ...over,
  })
}

const show = (climber: Holder = CLIMBER) =>
  renderWithProviders(<SkillWorkspace filters={FILTERS} climber={climber} profession="Tailoring" />)

/** Open the option named `name` from the overview; the run's details. */
async function choose(name: string) {
  await userEvent.click(await screen.findByRole('button', { name: `Choose ${name}` }))
  return screen.getByRole('region', { name: 'Run details' })
}

describe('SkillWorkspace', () => {
  it('starts with the best options side by side, the cheapest point first', async () => {
    const fetch = api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(cards.map((c) => c.getAttribute('aria-label'))).toEqual(['Choose Green Robe', 'Choose Linen Cap'])
    expect(within(cards[0]!).getByText('Best')).toBeInTheDocument()
    expect(within(cards[1]!).queryByText('Best')).not.toBeInTheDocument()
    expect(cards[0]).toHaveTextContent('Craft until 45 skill (~12 times), at which point Linen Cap becomes a cheaper option')
    // the cheaper recipe's item in its quality's colour, with its tooltip
    expect(within(cards[0]!).getByText('Linen Cap').closest('[data-quality]')).toHaveAttribute('data-quality', '2')
    // one amount: what the run comes to per skill point after selling, a loss in red with its minus sign
    expect(within(cards[0]!).getByText(/per skill point/)).toBeInTheDocument()
    const silver = within(cards[0]!).getByTitle('silver')
    expect(silver.parentElement).toHaveTextContent(/^-3 0$/) // 3600 copper spent for 12 points: 3s 0c each
    expect(silver.closest<HTMLElement>('[style]')?.style.color).toContain('red')
    expect(within(cards[0]!).queryByText(/after selling back/)).not.toBeInTheDocument()
    expect(within(cards[0]!).queryByText(/You know it|You must/)).not.toBeInTheDocument() // known: nothing to say
    expect(within(cards[0]!).queryByRole('img', { name: /Orange/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
    // each option's plan for the 14 crafts it opens with, fetched ahead
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).map((b) => [b.recipe_id, b.copies])).toEqual([
        [100, 14],
        [101, 14],
      ]),
    )
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('runs')).toBe('true')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/events')).map((b) => b.name)).toEqual(['next_up_shown']),
    )
  })

  it('opens a chosen option out into its run: what to make until when, why, what comes next, the checklist', async () => {
    const fetch = api()
    show()
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent(/Craft until 45 skill \(~12 times\), at which point Linen Cap becomes a cheaper option/)
    // the crafts to buy for: enough to reach the target four times in five
    expect(within(run).getByRole('textbox', { name: 'Crafts to buy for' })).toHaveValue('14')
    expect(within(run).getByText('82% chance to reach your target of 45 skill')).toBeInTheDocument()
    expect(within(run).queryByText(/Why this one|Then, at/)).not.toBeInTheDocument()
    // the checklist buys for the 14 crafts an unlucky run takes, grouped by who does what
    await waitFor(async () => expect(await bodies(fetch, '/api/evaluate')).toHaveLength(2)) // fetched ahead, once
    const [plan] = await bodies(fetch, '/api/evaluate')
    expect(plan).toMatchObject({ recipe_id: 100, copies: 14, runs: true, skill_crafters: ['Tailor Guy'] })
    expect(within(run).getByRole('group', { name: "Tailor Guy's steps" })).toBeInTheDocument()
    expect(within(run).getByText(/Sell back 2x/)).toBeInTheDocument() // for the 14 crafts
    // more crafts: better odds, and the checklist buys for them; past the odds sent, the last of them
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    expect(within(run).getByText('95% chance to reach your target of 45 skill')).toBeInTheDocument()
    await waitFor(async () => expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ copies: 20 }))
    await userEvent.type(input, '0')
    expect(within(run).getByText('95% chance to reach your target of 45 skill')).toBeInTheDocument()
    await waitFor(async () => expect((await bodies(fetch, '/api/events')).map((b) => b.name)).toContain('row_opened'))
    // and back to the options
    await userEvent.click(within(run).getByRole('button', { name: '← All options' }))
    expect(await screen.findByRole('region', { name: 'Your options' })).toBeInTheDocument()
  })

  it("names the character's Working Overtime ranks beside their skill, only when they have some", async () => {
    api()
    const { unmount } = show({ ...CLIMBER, name: 'Frell Ofelements', workingOvertime: { rank: 1, maxRank: 5 } })
    expect(await screen.findByText('(1/5 Working Overtime)')).toBeInTheDocument()
    expect(screen.getByText("Frell Ofelements'")).toBeInTheDocument()
    unmount()
    api()
    show()
    await screen.findByRole('region', { name: 'Your options' })
    expect(screen.queryByText(/Working Overtime/)).not.toBeInTheDocument()
    expect(screen.getByText("Tailor Guy's")).toBeInTheDocument()
  })

  it('says what to do to learn a recipe the climber lacks', async () => {
    const pattern: RankResult = { ...capRun, crafters: ['Someone Else'], learn_cost: 1200 }
    const unknown: RankResult = { ...beltRun, crafters: [], learn_cost: null }
    api({ '/api/rank': { ...ranked, results: [robeRun, pattern, unknown], total: 3 } })
    show()
    expect(await screen.findByText('You must buy the pattern (cost included)')).toBeInTheDocument()
    expect(screen.getByText('You must find the pattern (price unknown)')).toBeInTheDocument()
  })

  it('opens an option other than the best', async () => {
    api()
    show()
    const run = await choose('Linen Cap')
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Cap/)
  })

  it('scrolls the opened option fully into view as it grows', async () => {
    // jsdom has no layout: every box 100 px down and 1000 tall, in a 600 px window
    const scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
    const top = vi.spyOn(HTMLElement.prototype, 'offsetTop', 'get').mockReturnValue(100)
    const height = vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(1000)
    vi.stubGlobal('innerHeight', 600)
    try {
      api()
      show()
      await choose('Green Robe')
      // taller than the window: its top, less the margin
      await waitFor(() => expect(scrollTo).toHaveBeenLastCalledWith(0, 84))
    } finally {
      scrollTo.mockRestore()
      top.mockRestore()
      height.mockRestore()
      vi.unstubAllGlobals()
    }
  })

  it('copies the checklist as plain text', async () => {
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    api()
    show()
    const run = await choose('Green Robe')
    await userEvent.click(within(run).getByRole('button', { name: 'Copy steps' }))
    expect(writeText).toHaveBeenCalledTimes(1)
    const [text] = writeText.mock.calls[0] as unknown as [string]
    expect(text.split('\n')[0]).toBe(
      'Tailoring: Green Robe. Craft until 45 skill (~12 times), at which point Linen Cap becomes a cheaper option',
    )
    expect(text).toContain('1. Tailor Guy: Buy 12x Linen Cloth on the AH') // for the 14 crafts to buy for
    expect(await screen.findByRole('button', { name: 'Copied' })).toBeInTheDocument()
  })

  it('holds still when prices change, until refreshed', async () => {
    let version = 1
    const fetch = api({ '/api/status': () => status({ price_version: version }) })
    show()
    await screen.findByRole('region', { name: 'Your options' })
    const asked = urls(fetch, '/api/rank').length
    version = 2
    act(() => {
      focusManager.setFocused(false)
      focusManager.setFocused(true)
    })
    expect(await screen.findByText('Prices updated since this list was made')).toBeInTheDocument()
    // asked again on focus, perhaps, but still at the prices the list was made with
    expect(urls(fetch, '/api/rank').map((u) => u.searchParams.get('price_version'))).toEqual(
      Array(urls(fetch, '/api/rank').length).fill('1'),
    )
    expect(asked).toBeGreaterThan(0)
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('price_version')).toBe('2'))
    expect(screen.queryByText('Prices updated since this list was made')).not.toBeInTheDocument()
  })

  it('says to visit a trainer at the cap', async () => {
    api({ '/api/rank': { ...ranked, results: [], total: 0, then: null } })
    show({ ...CLIMBER, rank: 75 })
    expect(await screen.findByText("You're at your Tailoring cap (75)")).toBeInTheDocument()
    expect(screen.getByText(/Visit a Tailoring trainer to learn the next rank, then \/reload/)).toBeInTheDocument()
  })
})
