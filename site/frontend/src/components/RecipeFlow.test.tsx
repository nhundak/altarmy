import { act, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import type { ItemMap, RankResult } from '../api/client'
import { linen, robe, thread } from '../test/items'
import { robeResult } from '../test/results'
import { renderWithProviders } from '../test/utils'
import type { PlanEditing } from './ChoiceMenu'
import { RecipeFlow } from './RecipeFlow'

const editing: PlanEditing = { onChoose: vi.fn(), modified: false, onReset: vi.fn(), pending: false, error: null }

describe('RecipeFlow', () => {
  it('keeps a menu open while the plan and item details it shows are given again', async () => {
    let refresh = () => {}
    function Harness() {
      // what a parent re-rendering hands down: equal, but new objects
      const [shown, setShown] = useState<{ result: RankResult; items: ItemMap }>({
        result: robeResult,
        items: { '1': linen, '2': thread, '3': robe },
      })
      refresh = () => setShown((s) => ({ result: { ...s.result }, items: { ...s.items } }))
      return <RecipeFlow result={shown.result} items={shown.items} editing={editing} />
    }
    renderWithProviders(<Harness />)
    await userEvent.click(await screen.findByRole('button', { name: 'Change source of Coarse Thread' }))
    expect(await screen.findByRole('menuitem', { name: /Buy on the AH/ })).toBeInTheDocument()
    act(() => refresh())
    expect(screen.getByRole('menuitem', { name: /Buy on the AH/ })).toBeInTheDocument()
  })
})
