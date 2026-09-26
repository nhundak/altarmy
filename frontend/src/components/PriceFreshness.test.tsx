import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { GUEST, renderWithProviders } from '../test/utils'
import { PriceFreshness } from './PriceFreshness'

/** A server timestamp for `minutes` ago. */
const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString().slice(0, 19).replace('T', ' ')

describe('PriceFreshness', () => {
  it('shows a recent scan quietly', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(5)} />)
    const line = screen.getByText('Auction house prices scanned 5 min ago.')
    expect(line).not.toHaveStyle({ fontWeight: 500 })
    expect(line).toHaveAttribute('title', expect.stringMatching(/UTC$/))
  })

  it('warns when the scan is over an hour old', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(61)} />)
    const line = screen.getByText('Auction house prices are from a scan 1 h ago.')
    expect(line).toHaveStyle({ fontWeight: 500 })
    expect(line.querySelector('svg')).toBeInTheDocument()
  })

  it('warns when there is no scan', () => {
    renderWithProviders(<PriceFreshness lastScan={null} />)
    expect(screen.getByText('No auction house scan for this realm yet.')).toHaveStyle({ fontWeight: 500 })
  })

  it('links to the Upload page', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(90)} />, GUEST)
    expect(screen.getByRole('link', { name: 'Upload your scan' })).toHaveAttribute('href', '/upload')
  })
})
