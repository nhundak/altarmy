import { Notifications, notifications } from '@mantine/notifications'
import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { App } from './App'
import type { UpdateResult } from './api/client'
import { syncSeen, syncSeenKey } from './lib/syncNotice'
import { characters, status } from './test/status'
import { GUEST, LINKED, mockApi, renderWithProviders } from './test/utils'

const result: UpdateResult = {
  build: '1.60.1.70000',
  updated: true,
  items: 1234,
  recipes: 56,
  disenchant_rows: 0,
  vendor_items: 7,
}

function renderApp() {
  return renderWithProviders(
    <>
      <Notifications />
      <App />
    </>,
  )
}

function updateCalls(fetch: ReturnType<typeof mockApi>) {
  return fetch.mock.calls.map(([r]) => new URL(r.url)).filter((u) => u.pathname === '/api/game-data/update')
}

describe('automatic game data update', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    notifications.clean()
  })

  it('asks for the newest build once on load and toasts when it downloaded one', async () => {
    const fetch = mockApi({ '/api/game-data/update': result, '/api/status': status(), '/api/characters': characters })
    renderApp()
    expect(await screen.findByText('New game data downloaded')).toBeInTheDocument()
    expect(screen.getByText(/Loaded build 1\.60\.1\.70000: 1,234 items, 56 recipes/)).toBeInTheDocument()
    const calls = updateCalls(fetch)
    expect(calls).toHaveLength(1)
    expect(calls[0]?.searchParams.get('only_if_new')).toBe('true')
  })

  it('stays quiet when the database already has the newest build', async () => {
    const fetch = mockApi({ '/api/game-data/update': { ...result, updated: false }, '/api/status': status(), '/api/characters': characters })
    renderApp()
    await waitFor(() => expect(updateCalls(fetch)).toHaveLength(1))
    await new Promise((resolve) => setTimeout(resolve, 50)) // let the mutation settle
    expect(screen.queryByText('New game data downloaded')).not.toBeInTheDocument()
  })
})

describe('addon sync notifications', () => {
  afterEach(() => notifications.clean())

  function stale() {
    return { '/api/game-data/update': { ...result, updated: false }, '/api/characters': characters }
  }

  it('toasts what the sync imported since the page last saw the status', async () => {
    const before = status()
    localStorage.setItem(syncSeenKey('forever'), JSON.stringify(syncSeen(before)))
    mockApi({
      ...stale(),
      '/api/status': status({ data_version: 2, last_auctionator_sync: '2026-09-24 11:00:00' }),
    })
    renderApp()
    expect(await screen.findByText('Addon data imported')).toBeInTheDocument()
    expect(screen.getByText('Loaded Auctionator prices for ClassicBetaPvE.')).toBeInTheDocument()
    expect(JSON.parse(localStorage.getItem(syncSeenKey('forever')) ?? '')).toMatchObject({ data_version: 2 })
  })

  it('does not announce the data it finds on a first visit', async () => {
    mockApi({ ...stale(), '/api/status': status() })
    renderApp()
    await waitFor(() => expect(localStorage.getItem(syncSeenKey('forever'))).not.toBeNull())
    expect(screen.queryByText('Addon data imported')).not.toBeInTheDocument()
  })
})

describe('the shell by mode and tier', () => {
  const hostedApi = () =>
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/ah-blocked': { items: [], details: {} },
      '/api/favorites': { recipes: [] },
      '/api/keys': [],
      '/api/uploads': [],
      '/api/coverage': [],
      '/api/rank': { results: [], total: 0, items: {}, classes: {} },
    })
  const nav = () => within(screen.getByRole('navigation', { name: 'Pages' })).getAllByRole('link').map((l) => l.textContent)

  it('names the site Alt Army, links the addon page, and has no account controls in local mode', async () => {
    mockApi({ '/api/game-data/update': result, '/api/status': status(), '/api/characters': characters })
    renderApp()
    expect(screen.getByRole('link', { name: 'Alt Army, main page' })).toHaveAttribute('href', '/')
    expect(nav()).toEqual(['Manage'])
    expect(screen.queryByRole('button', { name: 'Sign in' })).not.toBeInTheDocument()
    expect(screen.queryByRole('radiogroup', { name: 'Game version' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Get the Addon' }))
    expect(await screen.findByRole('heading', { name: 'Get the Addon' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/addon')
  })

  it('opens with the two showcase cards, the profit one leading to the search', async () => {
    mockApi({ '/api/game-data/update': result, '/api/status': status(), '/api/characters': characters })
    renderApp()
    expect(screen.getByRole('link', { name: 'Alt Army' })).toHaveAttribute('href', '/addon')
    fireEvent.click(screen.getByRole('link', { name: 'Put your army to work' }))
    expect(window.location.pathname).toBe('/profit')
    expect(await screen.findByRole('button', { name: /^3 characters on/ })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Alt Army, main page' }))
    expect(await screen.findByRole('link', { name: 'Put your army to work' })).toBeInTheDocument()
  })

  it('gives anonymous users everything but API keys, with a way to sign in, and never syncs or updates game data', async () => {
    const fetch = hostedApi()
    window.history.pushState(null, '', '/profit')
    renderWithProviders(<App />, GUEST)
    expect(nav()).toEqual(['Upload', 'Manage'])
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: /^3 characters on/ })).toBeInTheDocument() // theirs, ready to rank
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Manage' }))
    expect(await screen.findByText('Never sold on the auction house')).toBeInTheDocument()
    expect(screen.getByText(/Create an account or sign in \(top right\) to make API keys/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Make key' })).not.toBeInTheDocument()
    expect(updateCalls(fetch)).toEqual([])
    expect(fetch.mock.calls.map(([r]) => new URL(r.url).pathname)).not.toContain('/api/keys')
  })

  it('gives signed-in users their AH blocks and API keys, without the local file sync', async () => {
    const fetch = hostedApi()
    window.history.pushState(null, '', '/manage')
    renderWithProviders(<App />, LINKED)
    expect(screen.queryByRole('button', { name: 'Sign in' })).not.toBeInTheDocument()
    expect(await screen.findByText('Never sold on the auction house')).toBeInTheDocument()
    expect(screen.getByText('Upload automatically')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Make key' })).toBeInTheDocument()
    expect(screen.queryByText('Addon data')).not.toBeInTheDocument()
    expect(screen.queryByText('Game data')).not.toBeInTheDocument()
    expect(updateCalls(fetch)).toEqual([])
  })

  it('opens the upload page in hosted mode only', async () => {
    hostedApi()
    window.history.pushState(null, '', '/upload')
    renderWithProviders(<App />, GUEST)
    expect(await screen.findByRole('heading', { name: 'Upload' })).toBeInTheDocument()
    expect(screen.getByText('Paste from Alt Army')).toBeInTheDocument()
  })
})

describe('theme toggle', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('switches between the dark and light schemes', () => {
    mockApi({ '/api/game-data/update': result, '/api/status': status(), '/api/characters': characters })
    renderApp()
    const root = document.documentElement
    const before = root.getAttribute('data-mantine-color-scheme')
    const toggle = screen.getByRole('button', { name: /Switch to (light|dark) theme/ })
    fireEvent.click(toggle)
    const after = root.getAttribute('data-mantine-color-scheme')
    expect(after).not.toBe(before)
    expect(screen.getByRole('button', { name: `Switch to ${before} theme` })).toBeInTheDocument()
  })
})
