import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { robe } from '../test/items'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { ManageTab } from './ManageTab'

function requests(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([r]) => r).filter((r) => new URL(r.url).pathname === pathname)
}

describe('ManageTab auction house list', () => {
  const routes = { '/api/status': status(), '/api/keys': [] }

  it('lists items never sold on the AH and removes them', async () => {
    const fetch = mockApi({
      ...routes,
      '/api/ah-blocked': { items: [{ item_id: 3, added_at: '2026-09-20 18:30:00' }], details: { '3': robe } },
      '/api/ah-blocked/3': { items: [], details: {} },
    })
    renderWithProviders(<ManageTab />)
    expect(await screen.findByText('Green Robe')).toBeInTheDocument()
    expect(screen.getByText(/added 2026-09-20 18:30:00 UTC/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Allow Green Robe on the auction house' }))
    await waitFor(() => expect(requests(fetch, '/api/ah-blocked/3')).toHaveLength(1))
    expect(requests(fetch, '/api/ah-blocked/3')[0]?.method).toBe('DELETE')
    expect(await screen.findByText(/Use the ⋯ menu on a search result/)).toBeInTheDocument()
  })

  it('explains how to add items when the list is empty', async () => {
    mockApi({ ...routes, '/api/ah-blocked': { items: [], details: {} } })
    renderWithProviders(<ManageTab />)
    expect(await screen.findByText(/Use the ⋯ menu on a search result/)).toBeInTheDocument()
  })
})
