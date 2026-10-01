import { screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderWithProviders } from '../test/utils'
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

  it('still shows a 29-minute-old scan quietly', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(29)} />)
    expect(screen.getByText('Auction house prices scanned 29 min ago.')).not.toHaveStyle({ fontWeight: 500 })
  })

  it('warns when the scan is over half an hour old', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(31)} />)
    const line = screen.getByText('Auction house prices are from a scan 31 min ago.')
    expect(line).toHaveStyle({ fontWeight: 500 })
    expect(line.querySelector('svg')).toBeInTheDocument()
  })

  it('warns when there is no scan', () => {
    renderWithProviders(<PriceFreshness lastScan={null} />)
    const line = screen.getByText(/^Nobody has scanned this auction house yet\. At the auction house, press Alt Army scan/)
    expect(line).toHaveStyle({ fontWeight: 500 })
  })
})
