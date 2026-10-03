import { screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderWithProviders } from '../test/utils'
import { ADDON_ZIP, AddonPage, CURSEFORGE_URL, WAGO_URL } from './Pages'

describe('AddonPage', () => {
  it('offers CurseForge, Wago and the zip, each as a card with its link', () => {
    renderWithProviders(<AddonPage />)
    expect(screen.getByRole('heading', { name: 'Get the Addon' })).toBeInTheDocument()
    const link = (card: string) => within(screen.getByRole('article', { name: card })).getByRole('link')
    expect(link('CurseForge')).toHaveAttribute('href', CURSEFORGE_URL)
    expect(link('Wago')).toHaveAttribute('href', WAGO_URL)
    expect(link('Download the zip')).toHaveAttribute('href', ADDON_ZIP)
    expect(ADDON_ZIP).toBe('https://github.com/ntower/altarmy/releases/latest/download/AltArmy_TBC.zip')
  })

  it("opens with the addon's showcase card as a banner: Get the Addon and a way back to the main page", () => {
    renderWithProviders(<AddonPage />)
    const card = screen.getByRole('article', { name: 'Get the Addon' })
    expect(within(card).getByRole('heading', { level: 1 })).toHaveTextContent('Get the Addon')
    expect(card).toHaveTextContent(/^Get the Addon← Back$/)
    expect(within(card).getByRole('link', { name: '← Back' })).toHaveAttribute('href', '/')
    expect(within(card).queryByRole('group')).not.toBeInTheDocument()
    expect(screen.queryByText(/Back to the search/)).not.toBeInTheDocument()
  })

  it('opens the stores in a new tab', () => {
    renderWithProviders(<AddonPage />)
    const store = within(screen.getByRole('article', { name: 'CurseForge' })).getByRole('link')
    expect(store).toHaveAttribute('target', '_blank')
    expect(store).toHaveAttribute('rel', 'noopener noreferrer')
  })
})
