import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import type { ItemMap, RankResult } from '../api/client'
import { linen, robe, thread } from '../test/items'
import { robeResult } from '../test/results'
import { mockApi, renderWithProviders } from '../test/utils'
import { MarketSection, useMarket } from './MarketSection'

const level = (price: number, quantity: number, counted = true) => ({
  price,
  quantity,
  counted,
  more: false,
  listings: 1,
  age: 2,
})

// Ten robes posted on the AH from linen bought up its ladder (only 8 listed) and a vendor's thread.
const posted: RankResult = {
  ...robeResult,
  best_exit: 'ah',
  likely_exit: 'ah',
  crafts: 10,
  cost: 3000,
  sell_options: [
    { kind: 'ah', profit: 6000 },
    { kind: 'vendor', profit: 2000 },
  ],
  tree: {
    ...robeResult.tree,
    inputs: [{ ...robeResult.tree.inputs[0]!, quantity: 10, cost: 2900, short: 2 }, robeResult.tree.inputs[1]!],
  },
}
const items: ItemMap = {
  '1': { ...linen, ah_price: 280, ah_quantity: 8, ah_levels: [level(280, 5), level(300, 3)], median_7d: 250, scans_7d: 4 },
  '2': thread,
  '3': { ...robe, ah_price: 950, ah_sell_price: 950, ah_quantity: 12, ah_levels: [level(940, 4), level(990, 8)] },
}

function Harness({ result }: { result: RankResult }) {
  const market = useMarket(result, 'gold', () => {})
  return (
    <MarketSection
      result={result}
      items={items}
      list={market.list}
      selected={market.selected}
      onSelect={market.select}
      watchedHours={0}
    />
  )
}

const tile = (name: RegExp) => screen.getByRole('button', { name })

describe('MarketSection', () => {
  it('opens on what is sold and switches to any item of the plan', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    const strip = screen.getByRole('group', { name: 'Items in this plan' })
    expect(within(strip).getAllByRole('button').map((b) => b.getAttribute('aria-pressed'))).toEqual([
      'false',
      'false',
      'true',
    ])
    expect(screen.getByText(/^We count on/)).toHaveTextContent(/for all 10/)
    // the linen's cue: two more bought than are listed
    expect(within(tile(/^Linen Cloth/)).getByText('2 short')).toBeInTheDocument()
    await userEvent.click(tile(/^Linen Cloth/))
    expect(tile(/^Linen Cloth/)).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByText(/^Buying 10 for/)).toHaveTextContent(/2 more than are listed, priced at the dearest 3 0/)
    expect(screen.getByText(/dearer than the usual/)).toHaveTextContent(/about 16% dearer than the usual 2 50/)
    await userEvent.click(tile(/^Coarse Thread/))
    expect(screen.getByText(/^Bought from a vendor/)).toBeInTheDocument()
  })

  it('shows the order book a click away: what a reagent buys of each level', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(tile(/^Linen Cloth/))
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    const rows = within(screen.getByRole('table')).getAllByRole('row')
    expect(rows[0]).toHaveTextContent('PriceUnitsListingsListed forYou buy')
    expect(rows.slice(1).map((r) => r.lastChild?.textContent)).toEqual(['5', '3'])
    expect(screen.getByRole('img', { name: /Price levels listed for Linen Cloth/ })).toBeInTheDocument()
    expect(screen.queryByRole('radio', { name: 'If I undercut' })).not.toBeInTheDocument()
  })

  it('offers the profit at each price for what is sold on the auction house', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    await userEvent.click(screen.getByRole('radio', { name: 'If I undercut' }))
    expect(screen.getByRole('img', { name: 'Session profit at each listing price' })).toBeInTheDocument()
  })

  it('tells more about the item: every way to sell, sales seen, how it is counted', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(screen.getByRole('button', { name: 'More about Green Robe' }))
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Ways to sell', 'Sales seen', 'How we count'])
    await userEvent.click(screen.getByRole('tab', { name: 'Sales seen' }))
    expect(screen.getByText(/^Sales here aren't watched yet/)).toBeInTheDocument()
  })
})
