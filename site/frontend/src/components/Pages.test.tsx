import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { renderWithProviders } from '../test/utils'
import { ADDON_ZIP, AddonPage, CURSEFORGE_URL, WAGO_URL } from './Pages'
import { SYNC_DOWNLOAD } from './SyncCard'

describe('AddonPage', () => {
  it('offers CurseForge, Wago and the zip, each as a card with its link', () => {
    renderWithProviders(<AddonPage />)
    const link = (card: string) => within(screen.getByRole('article', { name: card })).getByRole('link')
    expect(link('CurseForge')).toHaveAttribute('href', CURSEFORGE_URL)
    expect(link('Wago')).toHaveAttribute('href', WAGO_URL)
    expect(link('Download the zip')).toHaveAttribute('href', ADDON_ZIP)
    expect(ADDON_ZIP).toBe('https://github.com/ntower/altarmy/releases/latest/download/AltArmy_TBC.zip')
  })

  it('has no banner or way back, only the cards and the steps', () => {
    renderWithProviders(<AddonPage />)
    expect(screen.queryByRole('heading', { name: 'Get the Addon' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: '← Back' })).not.toBeInTheDocument()
  })

  it('opens the stores in a new tab', () => {
    renderWithProviders(<AddonPage />)
    const store = within(screen.getByRole('article', { name: 'CurseForge' })).getByRole('link')
    expect(store).toHaveAttribute('target', '_blank')
    expect(store).toHaveAttribute('rel', 'noopener noreferrer')
  })

  it('opens the export paste under Upload Now', async () => {
    renderWithProviders(<AddonPage />)
    expect(screen.getByText('Paste the text into the website.')).toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: /Alt Army export/ })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Upload Now' }))
    expect(screen.getByRole('textbox', { name: /Alt Army export/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Upload Now' })).not.toBeInTheDocument()
  })

  it('opens the file upload under Upload your scan', async () => {
    renderWithProviders(<AddonPage />)
    expect(screen.queryByText('AltArmy_TBC.lua for', { exact: false })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Upload your scan' }))
    expect(screen.getByRole('button', { name: 'Upload' })).toBeInTheDocument()
  })

  it("opens Alt Army Sync's setup from its link", async () => {
    renderWithProviders(<AddonPage />)
    await userEvent.click(screen.getByRole('button', { name: 'Alt Army Sync' }))
    expect(await screen.findByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
  })
})
