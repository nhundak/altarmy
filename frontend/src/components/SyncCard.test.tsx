import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { GUEST, LINKED, renderWithProviders } from '../test/utils'
import { SyncCard, SYNC_DOWNLOAD } from './SyncCard'

describe('SyncCard', () => {
  it('links the latest Alt Army Sync, which signs in with the account', () => {
    renderWithProviders(<SyncCard />, LINKED)
    expect(screen.getByRole('link', { name: 'Alt Army Sync for Windows' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    expect(SYNC_DOWNLOAD).toMatch(/releases\/latest\/download\/altarmy-sync\.exe$/)
    expect(screen.getByText(/signs in with your account's email and password/)).toBeInTheDocument()
    expect(screen.queryByText(/create one with Sign in/)).not.toBeInTheDocument()
  })

  it('tells a guest the app needs an account', () => {
    renderWithProviders(<SyncCard />, GUEST)
    expect(screen.getByText(/create one with Sign in \(top right\)/)).toBeInTheDocument()
  })
})
