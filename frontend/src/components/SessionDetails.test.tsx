import { fireEvent, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it } from 'vitest'
import type { RankResult } from '../api/client'
import { linen, robe as robeItem, thread } from '../test/items'
import { timedRobe } from '../test/results'
import { mockApi, renderWithProviders, shown } from '../test/utils'
import { ResultsTable } from './ResultsTable'

const items = { '1': linen, '2': thread, '3': robeItem }

const at = (
  id: string,
  kind: string,
  name: string,
  map_x: number | null,
  map_y: number | null,
  map_area: number | null = null,
) => ({ id, kind, name, map_x, map_y, map_area })

const stockton = at('ah', 'ah', 'Auctioneer Stockton', 71.4, 46.7, 1637)

/** The robe ranked as a session of the time settings' 20 crafts: the steps say 20x, and the details say where
 * to go. */
const session: RankResult = {
  ...timedRobe,
  crafts: 20,
  cost: 6000,
  revenue: 10000,
  profit: 4000,
  steps: timedRobe.steps.map((s) => ({ ...s, quantity: s.quantity * 20, value: s.value * 20 })),
  details: [
    { kind: 'start', who: '', step: null, location: stockton, retrieve: [], seconds: 0 },
    { kind: 'step', who: '', step: 0, location: null, retrieve: [], seconds: 0 },
    { kind: 'go', who: '', step: null, location: at('vendor:1', 'vendor', 'Thread Seller', 48.5, 71.2), retrieve: [], seconds: 13.6 },
    { kind: 'step', who: '', step: 1, location: null, retrieve: [], seconds: 0 },
    {
      kind: 'go',
      who: '',
      step: null,
      location: at('mailbox:1', 'mailbox', 'Mailbox', 50, 70.4, 1637),
      retrieve: [{ item_id: 1, count: 200 }],
      seconds: 0,
    },
    { kind: 'step', who: '', step: 2, location: null, retrieve: [], seconds: 0 },
    { kind: 'go', who: '', step: null, location: at('vendor:1', 'vendor', 'Thread Seller', 48.5, 71.2), retrieve: [], seconds: 0 },
    { kind: 'step', who: '', step: 3, location: null, retrieve: [], seconds: 0 },
  ],
}

type Body = { recipe_id: number; choices: object; copies?: number; city?: string }

/** The server: every session planned as `session`; returns the plan requests' bodies. */
function serve() {
  const asked: Body[] = []
  mockApi({
    '/api/evaluate': async (_: URL, request: Request) => {
      const body = (await request.clone().json()) as Body
      asked.push(body)
      return { result: { ...session, crafts: body.copies ?? 20 }, items }
    },
  })
  return asked
}

async function openRow(row: RankResult = session) {
  renderWithProviders(<ResultsTable results={[row]} items={items} />)
  await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
}

async function openSteps(row: RankResult = session) {
  await openRow(row)
  await userEvent.click(screen.getByText('Steps'))
}

const line = (text: string) =>
  screen.findByText((_, el) => el?.tagName === 'LI' && shown(el) === text, undefined, { timeout: 2000 })

describe('the Steps view plans a session', () => {
  beforeEach(() => localStorage.clear())

  it("shows the row's own session at once, in the city the row was timed in", async () => {
    const asked = serve()
    await openSteps()
    expect(await line('Purchase 200x Linen Cloth on the AH (40 0)')).toBeInTheDocument()
    expect(asked).toEqual([]) // the ranking already planned it
    expect(screen.getByLabelText('Copies')).toHaveValue('20')
    // each city says what the session makes per hour there
    expect(screen.getByRole('combobox', { name: 'City' })).toHaveValue('Orgrimmar (1g 23s 45c/hr)')
    expect(screen.queryByText(/^A batch of/)).not.toBeInTheDocument() // the summary above says it all
    expect(screen.getByText((_, el) => el?.tagName === 'P' && shown(el)?.startsWith('20 crafts: cost') === true)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it('re-plans for other copies or another city, and Reset goes back', async () => {
    const asked = serve()
    await openSteps()
    await line('Purchase 200x Linen Cloth on the AH (40 0)')
    fireEvent.change(screen.getByLabelText('Copies'), { target: { value: '5' } })
    await waitFor(() => expect(asked.at(-1)).toMatchObject({ copies: 5 }), { timeout: 2000 })
    expect(asked.at(-1)).not.toHaveProperty('city') // still wherever is quickest, as ranked
    await userEvent.click(screen.getByRole('combobox', { name: 'City' }))
    await userEvent.click(await screen.findByRole('option', { name: 'Thunder Bluff (5g 12s 34c/hr)' }))
    await waitFor(() => expect(asked.at(-1)).toMatchObject({ copies: 5, city: 'Thunder Bluff' }), { timeout: 2000 })
    const planned = asked.length
    await userEvent.click(screen.getByRole('button', { name: 'Reset' }))
    expect(screen.getByLabelText('Copies')).toHaveValue('20')
    expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
    expect(asked).toHaveLength(planned) // back to the row's own plan
  })

  it('spells out where to go in the detailed view, and remembers it', async () => {
    serve()
    await openSteps()
    await line('Purchase 200x Linen Cloth on the AH (40 0)')
    expect(screen.queryByText(/Run to/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('checkbox', { name: 'Detailed view' }))
    // to buy the thread (a 13.6 s run from the auction house), and later to sell the robe
    // each character starts where they stand, which takes no time
    expect(await line('Start at Auctioneer Stockton at 71.4, 46.7')).toBeInTheDocument()
    expect(await line('Run to Thread Seller at 48.5, 71.2. · 14 s')).toBeInTheDocument()
    expect(await line('Run to Thread Seller at 48.5, 71.2.')).toBeInTheDocument()
    expect(await line('Sell 20x Green Robe to Thread Seller (Gross 1 0 0 · Net 40 0)')).toBeInTheDocument()
    expect(await line('Purchase 20x Coarse Thread from Thread Seller (20 0)')).toBeInTheDocument()
    expect(await line('Run to Mailbox at 50.0, 70.4. Retrieve 200x Linen Cloth.')).toBeInTheDocument()
    expect(localStorage.getItem('altarmy-profit.steps.detailed')).toBe('true')
    expect(screen.getAllByRole('listitem').map((li) => shown(li)?.split(' ')[0])).toContain('Craft')
  })

  it('shows the zone map with the spot marked on hovering a run', async () => {
    localStorage.setItem('altarmy-profit.steps.detailed', 'true')
    serve()
    await openSteps()
    await userEvent.hover(await screen.findByText('Run to Mailbox at 50.0, 70.4'))
    expect(await screen.findByRole('img', { name: 'Map: Mailbox' })).toHaveAttribute(
      'src',
      '/maps/1637.jpg',
    )
    expect(screen.getByTestId('map-dot')).toHaveStyle({ left: '50%', top: '70.4%' })
    await userEvent.unhover(screen.getByText('Run to Mailbox at 50.0, 70.4'))
    await waitFor(() => expect(screen.queryByRole('img', { name: 'Map: Mailbox' })).not.toBeInTheDocument())
    // so does where a character starts
    await userEvent.hover(screen.getByText('Start at Auctioneer Stockton at 71.4, 46.7'))
    expect(await screen.findByRole('img', { name: 'Map: Auctioneer Stockton' })).toBeInTheDocument()
    await userEvent.unhover(screen.getByText('Start at Auctioneer Stockton at 71.4, 46.7'))
    // a run without a known zone map is plain text
    await userEvent.hover(screen.getAllByText(/Run to Thread Seller/)[0])
    expect(screen.queryAllByRole('img', { name: /^Map:/ })).toHaveLength(0)
  })
})

describe('the flow view plans the same session', () => {
  beforeEach(() => localStorage.clear())

  it('has the copies, city and reset, but no detailed view', async () => {
    const asked = serve()
    await openRow()
    expect(screen.getByLabelText('Copies')).toHaveValue('20')
    expect(screen.getByRole('combobox', { name: 'City' })).toBeInTheDocument()
    expect(screen.queryByRole('checkbox', { name: 'Detailed view' })).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Copies'), { target: { value: '3' } })
    await waitFor(() => expect(asked.at(-1)).toMatchObject({ copies: 3 }), { timeout: 2000 })
    await userEvent.click(screen.getByRole('button', { name: 'Reset' }))
    expect(screen.getByLabelText('Copies')).toHaveValue('20')
    expect(asked).toHaveLength(1)
  })

  it('has one Reset for the plan changes, the copies and the city', async () => {
    const asked = serve()
    await openRow()
    await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))
    fireEvent.change(screen.getByLabelText('Copies'), { target: { value: '7' } })
    await waitFor(() => expect(asked.at(-1)).toMatchObject({ copies: 7, choices: { 'r.1': 'ah' } }), { timeout: 2000 })
    expect(screen.getAllByRole('button', { name: 'Reset' })).toHaveLength(1)
    await userEvent.click(screen.getByRole('button', { name: 'Reset' }))
    expect(screen.getByLabelText('Copies')).toHaveValue('20')
    expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })
})

describe('every line of a session says how long it takes', () => {
  beforeEach(() => localStorage.clear())

  it('times switching characters and disenchanting', async () => {
    const disenchanted: RankResult = {
      ...session,
      best_exit: 'disenchant',
      steps: [
        { ...session.steps[3]!, who: 'Frell', via: 'disenchant', seconds: 100, lead_seconds: 70 },
      ],
      details: [
        { kind: 'switch', who: 'Frell', step: null, location: null, retrieve: [], seconds: 45 },
        { kind: 'start', who: 'Frell', step: null, location: stockton, retrieve: [], seconds: 0 },
        { kind: 'step', who: 'Frell', step: 0, location: null, retrieve: [], seconds: 0 },
      ],
    }
    localStorage.setItem('altarmy-profit.steps.detailed', 'true')
    await openSteps(disenchanted)
    expect(await line('Switch to Frell · 45 s')).toBeInTheDocument()
    expect(await line('Frell: Start at Auctioneer Stockton at 71.4, 46.7')).toBeInTheDocument()
    expect(await line('Frell: Disenchant 20x Green Robe · 1 min 10 s')).toBeInTheDocument()
    const sell = await screen.findByText((_, el) => el?.tagName === 'LI' && shown(el)?.startsWith('Frell: Sell materials') === true)
    expect(shown(sell)).toMatch(/· 30 s$/)
  })
})
