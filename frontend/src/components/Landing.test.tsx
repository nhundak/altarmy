import { act, fireEvent, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mockApi, renderWithProviders } from '../test/utils'
import { Landing } from './Landing'

describe('Landing', () => {
  afterEach(() => vi.useRealTimers())

  it('shows the addon and the profit search as two cards, each titled with a link to its page', () => {
    const fetch = mockApi({})
    renderWithProviders(<Landing />)
    expect(screen.getAllByRole('link').map((l) => l.getAttribute('href'))).toEqual(['/addon', '/profit'])
    const addon = screen.getByRole('article', { name: 'Alt Army' })
    expect(addon).toHaveTextContent(/remembers every one of your characters/)
    expect(addon).toHaveTextContent('Versions supported: Forever, and Burning Crusade')
    expect(addon).toHaveTextContent('Get the Addon')
    const profit = screen.getByRole('article', { name: 'Put your army to work' })
    expect(profit).toHaveTextContent(/Combine your character details/)
    expect(screen.getByRole('heading', { name: 'Put your army to work' })).toBeInTheDocument()

    fireEvent.click(within(profit).getByRole('link', { name: 'Put your army to work' }))
    expect(window.location.pathname).toBe('/profit')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('leaves modified clicks to the browser, so a card opens in a new tab', () => {
    mockApi({})
    renderWithProviders(<Landing />)
    fireEvent.click(screen.getByRole('link', { name: 'Alt Army' }), { ctrlKey: true })
    expect(window.location.pathname).toBe('/')
  })

  it('gives each card a carousel of screenshots whose buttons do not leave the page', () => {
    mockApi({})
    renderWithProviders(<Landing />)
    const shots = screen.getByRole('group', { name: 'Alt Army screenshots' })
    expect(within(shots).getByRole('img')).toHaveAttribute('src', '/landing/addon-summary.png')
    expect(within(shots).getAllByRole('button', { name: /^Screenshot \d of 7$/ })).toHaveLength(7)
    fireEvent.click(within(shots).getByRole('button', { name: 'Next screenshot' }))
    expect(within(shots).getAllByRole('img').map((i) => i.getAttribute('src'))).toContain('/landing/addon-search.png')
    expect(window.location.pathname).toBe('/')
    expect(screen.getByRole('group', { name: 'Put your army to work screenshots' })).toBeInTheDocument()
  })

  it('cycles the two carousels every six seconds, the profit one three seconds behind the addon one', () => {
    vi.useFakeTimers()
    mockApi({})
    renderWithProviders(<Landing />)
    const shown = (name: string) =>
      within(screen.getByRole('group', { name }))
        .getAllByRole('button', { name: /^Screenshot \d of \d$/ })
        .findIndex((b) => b.hasAttribute('aria-current'))
    const addon = 'Alt Army screenshots'
    const profit = 'Put your army to work screenshots'
    act(() => vi.advanceTimersByTime(6000))
    expect([shown(addon), shown(profit)]).toEqual([1, 0])
    act(() => vi.advanceTimersByTime(3000))
    expect([shown(addon), shown(profit)]).toEqual([1, 1])
    act(() => vi.advanceTimersByTime(3000))
    expect([shown(addon), shown(profit)]).toEqual([2, 1])
    act(() => vi.advanceTimersByTime(3000))
    expect([shown(addon), shown(profit)]).toEqual([2, 2])
  })
})
