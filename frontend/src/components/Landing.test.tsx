import { Notifications } from '@mantine/notifications'
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import type { UploadResult } from '../api/client'
import { characters, status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { Landing } from './Landing'

const noResults = { results: [], total: 0, items: {}, classes: {} }
const nobody = { groups: [], selection: { realm: 'Classic Beta PvE', faction: '' } }
const imported: UploadResult = {
  kind: 'altarmy',
  detail: '',
  characters: 3,
  groups: [{ realm: 'Classic Beta PvE', faction: 'Horde', characters: 1 }],
  realms: [],
}

function paths(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([r]) => r).filter((r) => new URL(r.url).pathname === pathname)
}

const cards = () => screen.queryByRole('group', { name: 'Ways to start' })

describe('Landing', () => {
  it('welcomes a new visitor with three ways to start and no search yet', async () => {
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody })
    renderWithProviders(<Landing />)
    expect(screen.getByRole('heading', { name: 'Put your army to work' })).toBeInTheDocument()
    expect(screen.getByText(/steps through all of your characters/)).toBeInTheDocument()
    const group = await screen.findByRole('group', { name: 'Ways to start' })
    expect(within(group).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
      'Import your characters',
      'Create manually',
      'Just browse',
    ])
    expect(screen.queryByRole('region', { name: 'Search' })).not.toBeInTheDocument()
    expect(paths(fetch, '/api/rank')).toEqual([])
  })

  it('just browsing folds the cards away, shows the search and remembers the choice', async () => {
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<Landing />)
    await userEvent.click(await screen.findByRole('button', { name: 'Just browse' }))
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(await screen.findByText('Browsing every recipe.')).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    await waitFor(() => expect(paths(fetch, '/api/rank')).toHaveLength(1))
    expect(JSON.parse(localStorage.getItem('altarmy-profit.landing.local') ?? '')).toEqual({ browsed: true })

    unmount()
    renderWithProviders(<Landing />)
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
  })

  it('imports pasted characters, then shows them above the search', async () => {
    let have = false
    const fetch = mockApi({
      '/api/status': () => status({ characters: have ? 3 : 0, data_version: have ? 2 : 1 }),
      '/api/characters': () => (have ? characters : nobody),
      '/api/uploads/paste': () => {
        have = true
        return imported
      },
      '/api/rank': noResults,
    })
    renderWithProviders(
      <>
        <Notifications />
        <Landing />
      </>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Import your characters' }))
    const box = await screen.findByRole('textbox', { name: 'Alt Army export' })
    expect(screen.getByText('/altarmy export')).toBeInTheDocument()
    // the other two ways stay at hand, smaller
    expect(screen.getByRole('button', { name: 'Just browse' })).toBeInTheDocument()
    await userEvent.type(box, 'AAX1:abc')
    await userEvent.click(screen.getByRole('button', { name: 'Import characters' }))
    expect(await screen.findByText('Characters imported')).toBeInTheDocument()
    expect(await screen.findByText(/^3 characters on Classic Beta PvE/)).toBeInTheDocument()
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    const [post] = paths(fetch, '/api/uploads/paste')
    expect(await post?.json()).toEqual({ text: 'AAX1:abc' })
  })

  it('starts folded with the search when the user already has characters', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<Landing />)
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '3 characters on Classic Beta PvE (Horde), Dreamscythe (Horde)' })).toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Add a character' }))
    expect(await screen.findByRole('textbox', { name: 'Name' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Back to the three ways to start' }))
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
  })

  it('opens the summary to show every character, and removes one', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<Landing />)
    const summary = await screen.findByRole('button', { name: /^3 characters on/ })
    expect(summary).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByText('Tailor Guy')).not.toBeInTheDocument()
    await userEvent.click(summary)
    expect(summary).toHaveAttribute('aria-expanded', 'true')
    expect(await screen.findByText('Tailor Guy')).toBeInTheDocument()
    expect(screen.getByText(/Cooking 1\/75, Tailoring 50\/75/)).toBeInTheDocument()
    expect(screen.getByText('Frell')).toBeInTheDocument() // every realm, not just the selected one
    expect(screen.getByText('Dreamscythe (Horde)')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Remove Frell' }))
    await waitFor(() => expect(fetch.mock.calls.some(([r]) => r.method === 'DELETE')).toBe(true))
    const del = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'DELETE')
    expect(new URL(del!.url).searchParams.toString()).toBe('game_version=forever&realm=Dreamscythe&name=Frell')

    await userEvent.click(summary)
    await waitFor(() => expect(screen.queryByText('Tailor Guy')).not.toBeInTheDocument())
  })
})
