import { Notifications } from '@mantine/notifications'
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import type { UploadResult } from '../api/client'
import { characters, status } from '../test/status'
import { GUEST, mockApi, renderWithProviders } from '../test/utils'
import { SYNC_DOWNLOAD } from './SyncCard'
import { ProfitPage } from './Profit'

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
const hero = () => screen.queryByRole('heading', { name: 'Put your army to work' })

describe('ProfitPage', () => {
  it('welcomes a new visitor with the banner, three ways to start and no search yet', async () => {
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('heading', { name: 'Put your army to work' })).toBeInTheDocument()
    expect(screen.getByText(/steps through all of your characters/)).toBeInTheDocument()
    const group = await screen.findByRole('group', { name: 'Ways to start' })
    expect(within(group).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
      'Import your characters',
      'Auto-import',
      'Skip for now',
    ])
    expect(screen.queryByRole('region', { name: 'Search' })).not.toBeInTheDocument()
    expect(paths(fetch, '/api/rank')).toEqual([])
  })

  it('skipping folds the cards away, asks for a goal, then ranks, remembering both', async () => {
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<ProfitPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Skip for now' }))
    const search = await screen.findByRole('region', { name: 'Search' })
    expect(await screen.findByText('Browsing every recipe.')).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    await waitFor(() => expect(hero()).not.toBeInTheDocument())
    expect(JSON.parse(localStorage.getItem('altarmy-profit.landing.g1') ?? '')).toEqual({ browsed: true })
    // nothing is ranked until the goal is known
    const goals = within(search).getByRole('group', { name: 'Your goal' })
    expect(paths(fetch, '/api/rank')).toEqual([])
    await userEvent.click(within(goals).getByRole('button', { name: 'Maximize profit' }))
    await waitFor(() => expect(paths(fetch, '/api/rank')).toHaveLength(1))
    expect(new URL(paths(fetch, '/api/rank')[0]!.url).searchParams.get('sort')).toBe('rate')

    unmount()
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(await screen.findByText('Goal: Maximize profit.')).toBeInTheDocument()
    expect(screen.queryByRole('group', { name: 'Your goal' })).not.toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
    expect(hero()).not.toBeInTheDocument()
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
        <ProfitPage />
      </>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Import your characters' }))
    const box = await screen.findByRole('textbox', { name: 'Alt Army export' })
    expect(screen.getByText('/altarmy export')).toBeInTheDocument()
    // the other two ways stay at hand, smaller
    expect(screen.getByRole('button', { name: 'Skip for now' })).toBeInTheDocument()
    expect(screen.getByText('Set up Alt Army Sync.')).toBeInTheDocument()
    expect(screen.getByText('Every recipe, no character optimization.')).toBeInTheDocument()
    await userEvent.type(box, 'AAX1:abc')
    await userEvent.click(screen.getByRole('button', { name: 'Import characters' }))
    expect(await screen.findByText('Characters imported')).toBeInTheDocument()
    expect(await screen.findByText(/^3 characters on Classic Beta PvE/)).toBeInTheDocument()
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    const [post] = paths(fetch, '/api/uploads/paste')
    expect(await post?.json()).toEqual({ text: 'AAX1:abc' })
  })

  it('starts folded with the search when the user already has characters, and sets up auto-import', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '3 characters on Classic Beta PvE (Horde), Dreamscythe (Horde)' })).toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
    expect(hero()).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Auto-import' }))
    expect(await screen.findByRole('heading', { name: 'Auto-import' })).toBeInTheDocument()
    expect(screen.getByText(/never changes a game file/)).toBeInTheDocument()
    expect(screen.getByText('Signed in.')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Sign in to the app' })).toBeInTheDocument()
    expect(screen.getByText(/never your password/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(screen.getByRole('button', { name: 'Back to the three ways to start' }))
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
  })

  it('offers a guest an account first, which keeps what the browser has', async () => {
    mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody })
    renderWithProviders(<ProfitPage />, GUEST)
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-import' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Sign in or create an account' }))
    expect(await screen.findByRole('dialog', { name: 'Your account' })).toBeInTheDocument()
    expect(screen.getByText(/tick Create a new account there/)).toBeInTheDocument()
  })

  it("moves on by itself when Alt Army Sync's first upload brings characters in", async () => {
    let have = false
    mockApi({
      '/api/status': () => status({ characters: have ? 3 : 0, data_version: have ? 2 : 1 }),
      '/api/characters': () => (have ? characters : nobody),
      '/api/rank': noResults,
    })
    renderWithProviders(
      <>
        <Notifications />
        <ProfitPage />
      </>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-import' }))
    expect(await screen.findByRole('heading', { name: 'Auto-import' })).toBeInTheDocument()
    have = true
    window.dispatchEvent(new Event('visibilitychange')) // what the status poll would notice
    expect(await screen.findByText('Characters uploaded')).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: /^3 characters on/ })).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
  })

  it('offers Continue instead of Skip for now once the user has characters', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-import' }))
    expect(await screen.findByRole('heading', { name: 'Auto-import' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Skip for now' })).not.toBeInTheDocument()
    const cont = screen.getByRole('button', { name: 'Continue' })
    expect(within(cont).getByText('Done adding characters.')).toBeInTheDocument()
    await userEvent.click(cont)
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    expect(screen.getByRole('button', { name: /^3 characters on/ })).toBeInTheDocument()
  })

  it('opens the summary to show every character, and removes one', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
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
