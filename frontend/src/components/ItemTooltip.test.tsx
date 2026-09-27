import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { renderWithProviders, shown } from '../test/utils'
import { hammer, helm, linen, robe, thread } from '../test/items'
import { ItemLink, ItemTooltip, RecipeTooltip } from './ItemTooltip'

/** The element whose own text content (including children) is exactly `text`. */
const line = (text: string) => screen.getByText((_, el) => shown(el) === text && el!.children.length > 0)

describe('ItemTooltip', () => {
  it('shows armor, stats and the green lines in game order', () => {
    const { container } = renderWithProviders(<ItemTooltip item={helm} />)
    const lines = Array.from(container.querySelectorAll('div > div')).map((el) => el.textContent)
    const at = (text: string) => lines.findIndex((l) => l === text)
    expect(at('565 Armor')).toBeGreaterThan(at('Head'))
    expect(at('+18 Strength')).toBeGreaterThan(at('565 Armor'))
    expect(at('Requires Level 56')).toBeGreaterThan(at('+18 Strength'))
    expect(at('Equip: Improves your chance to get a critical strike by 2%.')).toBeGreaterThan(
      at('Requires Level 56'),
    )
    expect(at('Equip: Improves your chance to hit by 2%.')).toBeGreaterThan(
      at('Equip: Improves your chance to get a critical strike by 2%.'),
    )
    expect(screen.getByText('Equip: Improves your chance to hit by 2%.').className).toContain('green')
  })

  it('shows a weapon as damage, speed and dps', () => {
    renderWithProviders(<ItemTooltip item={hammer} />)
    expect(screen.getByText('46 - 86 Damage')).toBeInTheDocument()
    expect(screen.getByText('Speed 2.80')).toBeInTheDocument()
    expect(screen.getByText('(23.6 damage per second)')).toBeInTheDocument()
    expect(screen.queryByText(/Armor/)).not.toBeInTheDocument()
  })

  it('shows the in-game lines for an item', () => {
    renderWithProviders(<ItemTooltip item={robe} />)
    expect(screen.getByText('Green Robe')).toHaveStyle({ color: '#1eff00' })
    expect(screen.getByText('Binds when equipped')).toBeInTheDocument()
    expect(screen.getByText('Chest')).toBeInTheDocument()
    expect(screen.getByText('Cloth')).toBeInTheDocument()
    expect(screen.getByText('Requires Level 12')).toBeInTheDocument()
    expect(screen.getByText('Requires Tailoring (50)')).toBeInTheDocument()
    expect(screen.getByText('"Soft and green."')).toBeInTheDocument()
    expect(line('Sell Price: 2 16')).toBeInTheDocument()
    expect(screen.queryByText(/Auction:|Vendor:/)).not.toBeInTheDocument()
    expect(screen.getByRole('presentation')).toHaveAttribute(
      'src',
      'https://wow.zamimg.com/images/wow/icons/large/inv_chest_cloth_39.jpg',
    )
  })

  it('adds the auction price and leaves out empty lines', () => {
    renderWithProviders(<ItemTooltip item={linen} />)
    expect(line('Auction: 20')).toBeInTheDocument()
    expect(screen.queryByText(/Binds|Requires|Armor|Damage|Equip/)).not.toBeInTheDocument()
    expect(screen.queryByRole('presentation')).not.toBeInTheDocument()
  })

  it('adds the 7-day median when crafts sell below the auction price', () => {
    renderWithProviders(<ItemTooltip item={{ ...linen, ah_sell_price: 15 }} />)
    expect(line('Auction: 20')).toBeInTheDocument()
    expect(line('Sells for (7-day median): 15')).toBeInTheDocument()
  })

  it('adds the vendor price of vendor-sold items', () => {
    renderWithProviders(<ItemTooltip item={thread} />)
    expect(line('Vendor: 1 0')).toBeInTheDocument()
  })

  it('shows reagents above the crafted item on a recipe', () => {
    const items = { '1': linen, '2': thread, '3': robe }
    const reagents = [
      { item_id: 1, count: 10 },
      { item_id: 2, count: 1 },
    ]
    renderWithProviders(
      <RecipeTooltip
        name="Green Robe"
        profession="Tailoring"
        reagents={reagents}
        output={robe}
        items={items}
      />,
    )
    expect(screen.getByText('Tailoring')).toBeInTheDocument()
    expect(screen.getByText('Reagents: Linen Cloth (10), Coarse Thread')).toBeInTheDocument()
    expect(screen.getByText('Binds when equipped')).toBeInTheDocument()
  })

  it('opens on hover of an item link', async () => {
    renderWithProviders(<ItemLink item={robe} />)
    expect(screen.queryByText('Binds when equipped')).not.toBeInTheDocument()
    await userEvent.hover(screen.getByText('Green Robe'))
    expect(await screen.findByText('Binds when equipped')).toBeInTheDocument()
  })
})
