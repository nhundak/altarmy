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
import { BARTERING, WORKING_OVERTIME } from '../lib/talents'
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
const bootsRun: RankResult = { ...beltRun, recipe_id: 103, recipe: 'Linen Boots', output_item_id: 9004, output_name: 'Linen Boots' }
// After the robe's run: the belt's, then the boots'.
const ranked = { results: [robeRun, capRun], total: 2, items, classes: {}, learn: {}, chain: [beltRun, bootsRun] }

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
const overtime = (rank: number) => ({ spellId: WORKING_OVERTIME, name: 'Working Overtime', rank, maxRank: 5 })
const bartering = (rank: number) => ({ spellId: BARTERING, name: 'Bartering', rank, maxRank: 2 })

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

/** Open the option named `name` from the overview, picking it among the others first unless it is the one to craft
 * now; the run's details. */
async function choose(name: string) {
  const options = await screen.findByRole('region', { name: 'Your options' })
  if (!within(options).queryByRole('button', { name: `Choose ${name}` })) {
    await userEvent.click(within(options).getByRole('button', { name: 'Show me other options' }))
  }
  // side by side, a click picks it; the one to craft now opens
  if (within(options).getAllByRole('button', { name: /^Choose / }).length > 1) {
    await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  }
  await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  // already side by side, that click only picked it
  if (!screen.queryByRole('region', { name: 'Run details' })) {
    await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  }
  return screen.getByRole('region', { name: 'Run details' })
}

/** The chain's recipes, in order. */
const chainNames = (chain: HTMLElement) =>
  within(chain)
    .getAllByRole('article')
    .map((e) => e.getAttribute('aria-label'))

describe('SkillWorkspace', () => {
  it('starts with the best option and what comes after it, the others side by side on asking', async () => {
    api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Green Robe',
    ])
    // the runs that follow it, nothing to click on them
    let chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chainNames(chain)).toEqual(['Linen Belt', 'Linen Boots'])
    // each arrow says the skill the next run starts at: where the one before stops
    expect(within(chain).getAllByText(/^At \d+ skill$/).map((e) => e.textContent)).toEqual(['At 45 skill', 'At 45 skill'])
    expect(within(chain).queryByRole('button')).not.toBeInTheDocument()
    expect(chain).not.toHaveAttribute('aria-disabled')
    // the others side by side, the cheapest point first, the chain muted until one is picked
    await userEvent.click(within(options).getByRole('button', { name: 'Show me other options' }))
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(cards.map((c) => c.getAttribute('aria-label'))).toEqual(['Choose Green Robe', 'Choose Linen Cap'])
    expect(within(cards[0]!).getByText('Best')).toBeInTheDocument()
    expect(within(cards[1]!).queryByText('Best')).not.toBeInTheDocument()
    chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chain).toHaveAttribute('aria-disabled', 'true')
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
  })

  it('shows each option as picking it gives, those before it passed over', async () => {
    // listed, the cap stops where the robe gets cheaper; as an option, the robe passed over, at 60
    const asOption: RankResult = { ...capRun, crafts: 30, stop_skill: 60, overtaken_by: 'Linen Boots', overtaken_by_item: 9004 }
    api({ '/api/rank': { ...ranked, options: [robeRun, asOption] } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: 'Show me other options' }))
    expect(screen.getByRole('button', { name: 'Choose Linen Cap' })).toHaveTextContent(
      'Craft until 60 skill (~30 times), at which point Linen Boots becomes a cheaper option',
    )
  })

  it('shows four more runs after the chain on asking', async () => {
    const run = (i: number): RankResult => ({ ...beltRun, recipe_id: 200 + i, recipe: `Run ${i}`, output_name: `Run ${i}` })
    const runs = Array.from({ length: 10 }, (_, i) => run(i + 1))
    const fetch = api({
      '/api/rank': (url: URL) => ({ ...ranked, chain: runs.slice(0, Number(url.searchParams.get('chain_length') ?? 4)) }),
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chainNames(chain)).toEqual(['Run 1', 'Run 2', 'Run 3', 'Run 4'])
    await userEvent.click(within(chain).getByRole('button', { name: 'Show more' }))
    await waitFor(() => expect(chainNames(chain)).toHaveLength(8))
    // the longer chain follows the best, the one crafted now
    const asked = urls(fetch, '/api/rank').find((u) => u.searchParams.get('chain_length'))
    expect([asked?.searchParams.get('chain_from'), asked?.searchParams.get('chain_length')]).toEqual(['100', '8'])
    await userEvent.click(within(chain).getByRole('button', { name: 'Show more' }))
    await waitFor(() => expect(chainNames(chain)).toHaveLength(10))
    // fewer than asked for: the chain ended
    expect(within(chain).queryByRole('button', { name: 'Show more' })).not.toBeInTheDocument()
  })

  it('makes a picked option the one to craft now, with what comes after it', async () => {
    // without the robe, passed over, the cap's run goes on to 60, where the boots take over
    const longer: RankResult = { ...capRun, crafts: 30, stop_skill: 60, overtaken_by: 'Linen Boots', overtaken_by_item: 9004 }
    const capChain = { ...ranked, results: [longer], chain: [bootsRun], chain_start: longer }
    const fetch = api({
      '/api/rank': (url: URL) => (url.searchParams.get('chain_from') === '101' ? capChain : ranked),
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Show me other options' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    // folded back around it
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Linen Cap',
    ])
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    await waitFor(() => expect(chainNames(chain)).toEqual(['Linen Boots']))
    expect(chain).not.toHaveAttribute('aria-disabled')
    const asked = urls(fetch, '/api/rank').find((u) => u.searchParams.get('chain_from'))
    expect(asked?.searchParams.get('chain_from')).toBe('101')
    expect(asked?.searchParams.get('top')).toBe('1')
    expect(asked?.searchParams.getAll('skip')).toEqual(['100'])
    const card = within(options).getByRole('button', { name: 'Choose Linen Cap' })
    expect(card).toHaveTextContent('Craft until 60 skill (~30 times), at which point Linen Boots becomes a cheaper option')
    // opened and closed, it is still the one to craft now
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    const run = screen.getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Cap/)
    expect(run).toHaveTextContent(/Craft until 60 skill/) // the run as it stands after the pick
    await userEvent.click(within(run).getByRole('button', { name: '← All options' }))
    const back = await screen.findByRole('region', { name: 'Your options' })
    expect(within(back).getByRole('button', { name: 'Choose Linen Cap' })).toBeInTheDocument()
  })

  it('says what the best run is worth and how far it goes', async () => {
    const fetch = api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
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
    expect(screen.queryByText(/after this run/)).not.toBeInTheDocument() // the header stays as it was
    // the checklist buys for the 14 crafts an unlucky run takes, grouped by who does what
    await waitFor(async () => expect(await bodies(fetch, '/api/evaluate')).toHaveLength(2)) // fetched ahead, once
    const [plan] = await bodies(fetch, '/api/evaluate')
    expect(plan).toMatchObject({ recipe_id: 100, copies: 14, runs: true, skill_crafters: ['Tailor Guy'] })
    // the plan opens as its steps, the flow chart a click away
    const views = within(run).getByRole('radiogroup', { name: 'Show the plan as' })
    const [first, second] = within(views).getAllByRole('radio')
    expect([first, second]).toEqual([within(views).getByLabelText('Steps'), within(views).getByLabelText('Flowchart')])
    expect(within(views).getByLabelText('Steps')).toBeChecked()
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

  it('says how many of the skill points counted on come from Working Overtime, after the odds', async () => {
    // the ranked run's 12 crafts expect 0.5 points from the talent; the plan for the 14 bought for, 0.6
    api({
      '/api/rank': { ...ranked, results: [{ ...robeRun, skill_ups_bonus: 0.48 }, capRun] },
      '/api/evaluate': () => ({ result: { ...scaleRun(robeRun, 14), skill_ups_bonus: 0.56 }, items }),
    })
    show({ ...CLIMBER, talents: [overtime(1)] })
    const run = await choose('Green Robe')
    expect(
      await within(run).findByText(
        '82% chance to reach your target of 45 skill (includes ~0.6 skill points from Working Overtime)',
      ),
    ).toBeInTheDocument()
    expect(within(run).queryByText(/· .* points from Working Overtime/)).not.toBeInTheDocument()
  })

  it("names the character's crafting talents beside their skill, only when they have some", async () => {
    api()
    const { unmount } = show({ ...CLIMBER, name: 'Frell Ofelements', talents: [overtime(1), bartering(2)] })
    expect(await screen.findByText('(1/5 Working Overtime, 2/2 Bartering)')).toBeInTheDocument()
    expect(screen.getByText("Frell Ofelements'")).toBeInTheDocument()
    unmount()
    api()
    show()
    await screen.findByRole('region', { name: 'Your options' })
    expect(screen.queryByText(/Working Overtime/)).not.toBeInTheDocument()
    expect(screen.getByText("Tailor Guy's")).toBeInTheDocument()
  })

  it('says what each talent does when they are hovered', async () => {
    api()
    show({ ...CLIMBER, talents: [overtime(2), bartering(1)] })
    await userEvent.hover(await screen.findByText('(2/5 Working Overtime, 1/2 Bartering)'))
    const tooltip = await screen.findByRole('tooltip')
    expect(within(tooltip).getByText('Working Overtime')).toBeInTheDocument()
    expect(within(tooltip).getByText('Rank 2/5')).toBeInTheDocument()
    expect(within(tooltip).getByText('Increases your chance to gain a skill increase by 8%')).toBeInTheDocument()
    expect(within(tooltip).getByText('Bartering')).toBeInTheDocument()
    expect(within(tooltip).getByText('Rank 1/2')).toBeInTheDocument()
    expect(within(tooltip).getByText('Reduces the gold price of items from all vendors by 5%')).toBeInTheDocument()
  })

  it('says what to do to learn a recipe the climber lacks', async () => {
    const pattern: RankResult = { ...capRun, crafters: ['Someone Else'], learn_cost: 1200 }
    const unknown: RankResult = { ...beltRun, crafters: [], learn_cost: null }
    const vendor = {
      kind: 'vendor',
      name: 'Rann Flamespinner',
      zone: 'Orgrimmar',
      area: 1637,
      map_x: 63.2,
      map_y: 51.5,
      side: '',
      limited: false,
      chance: 0,
      count: 0,
      levels: '',
    }
    const learn = {
      '101': {
        source: 'recipe',
        skill: 50,
        profession: 'Tailoring',
        items: [{ item_id: 9001, name: 'Pattern: Linen Cap', price: 1200, limited: false, places: [vendor] }],
      },
    }
    api({ '/api/rank': { ...ranked, results: [robeRun, pattern, unknown], total: 3, learn } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: 'Show me other options' }))
    // the cards warn of a pattern nobody can price, and say one whose cost is counted must be trained
    expect(screen.getByText('You must find the pattern (price unknown)')).toBeInTheDocument()
    const card = screen.getByRole('button', { name: 'Choose Linen Cap' })
    expect(within(card).getByText('You will need to train this recipe (included in the cost)')).toBeInTheDocument()
    const run = await choose('Linen Cap')
    // the run names what the pattern costs
    expect(within(run).getByText(/You must buy the pattern/)).toHaveTextContent(/^You must buy the pattern \(12 0\)/)
    // and the checklist starts with buying it from its vendor, the zone map on hover
    const steps = within(run).getByRole('group', { name: "Tailor Guy's steps" })
    const first = within(steps).getAllByRole('listitem')[0]!
    expect(first).toHaveTextContent(
      /^Buy Pattern: Linen Cap from Rann Flamespinner, Orgrimmar at 63\.2, 51\.5 \(12 0\)$/,
    )
    await userEvent.hover(within(first).getByText(/Rann Flamespinner/))
    expect(await screen.findByRole('img', { name: /Rann Flamespinner/ })).toBeInTheDocument()
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

  it('opens a card of the full list as its run, and goes back to the list', async () => {
    const many = [robeRun, capRun, beltRun, { ...beltRun, recipe_id: 103, recipe: 'Linen Boots', output_name: 'Linen Boots' }]
    api({ '/api/rank': { ...ranked, results: [...many, { ...beltRun, recipe_id: 104, recipe: 'Linen Bag', output_item_id: 9002, output_name: 'Linen Bag' }], total: 5 } })
    show()
    // only once the options are side by side
    await screen.findByRole('region', { name: 'Your options' })
    expect(screen.queryByRole('button', { name: 'See all 5 options' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show me other options' }))
    await userEvent.click(screen.getByRole('button', { name: 'See all 5 options' }))
    expect(screen.queryByRole('region', { name: 'What comes after' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Choose Linen Bag' }))
    const run = screen.getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent('Linen Bag')
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    await userEvent.click(within(run).getByRole('button', { name: '← All options' }))
    expect(await screen.findByRole('button', { name: 'Choose Linen Bag' })).toBeInTheDocument() // the list again
  })

  it('shows no spinner while the plan fetched ahead is on its way, only for a count the user types', async () => {
    api({ '/api/evaluate': () => new Promise(() => {}) }) // never answers
    show()
    const run = await choose('Green Robe')
    expect(within(run).getByText(/Sell back 2x/)).toBeInTheDocument() // the ranked run, in proportion
    await new Promise((r) => setTimeout(r, 500)) // past the count's debounce
    expect(within(run).queryByLabelText('Planning')).not.toBeInTheDocument()
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    expect(await within(run).findByLabelText('Planning')).toBeInTheDocument()
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

  it("changes a reagent's source in the run, re-costed, until Reset", async () => {
    const onAh = {
      ...scaleRun(robeRun, 14),
      cost: 5000,
      profit: -5000,
      steps: robeRun.steps.map((s) => (s.item_id === 2 && s.action === 'buy' ? { ...s, via: 'ah', value: -150 } : s)),
    }
    const fetch = api({
      '/api/evaluate': async (_: URL, request: Request) => {
        const body = (await request.clone().json()) as { choices: Record<string, string> }
        return { result: Object.keys(body.choices).length ? onAh : { ...scaleRun(robeRun, 14), cost: 4200 }, items }
      },
    })
    show()
    const run = await choose('Green Robe')
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    expect(screen.getAllByRole('menuitem').map((m) => m.textContent)).toEqual([
      expect.stringMatching(/^✓Buy from a vendor/),
      expect.stringMatching(/^Buy on the AH/),
    ])
    await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))

    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ recipe_id: 100, copies: 14, runs: true, choices: { 'r.1': 'ah' } }),
    )
    expect(await within(run).findByText((_, el) => el?.tagName === 'LI' && /Coarse Thread on the AH/.test(el.textContent ?? ''))).toBeInTheDocument()
    expect(within(run).getByText('Changed plan')).toBeInTheDocument()

    await userEvent.click(within(run).getByRole('button', { name: 'Reset' }))
    expect(await within(run).findByText((_, el) => el?.tagName === 'LI' && /Coarse Thread from a vendor/.test(el.textContent ?? ''))).toBeInTheDocument()
    expect(within(run).queryByText('Changed plan')).not.toBeInTheDocument()
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it('offers the menus in the flow chart too, and forgets the changes on another option', async () => {
    api()
    show()
    let run = await choose('Green Robe')
    await userEvent.click(within(run).getByRole('radio', { name: 'Flowchart' }))
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))
    expect(await within(run).findByRole('button', { name: 'Reset' })).toBeInTheDocument()
    await userEvent.click(within(run).getByRole('button', { name: '← All options' }))
    run = await choose('Linen Cap')
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it('says to visit a trainer at the cap', async () => {
    api({ '/api/rank': { ...ranked, results: [], total: 0, chain: [] } })
    show({ ...CLIMBER, rank: 75 })
    expect(await screen.findByText("You're at your Tailoring cap (75)")).toBeInTheDocument()
    expect(screen.getByText(/Visit a Tailoring trainer to learn the next rank, then \/reload/)).toBeInTheDocument()
  })
})
