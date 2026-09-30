import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { renderWithProviders } from '../test/utils'
import { PriceFreshness } from './PriceFreshness'

/** A server timestamp for `minutes` ago. */
const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString().slice(0, 19).replace('T', ' ')

describe('PriceFreshness', () => {
  it('shows a recent scan quietly', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(5)} onUpload={vi.fn()} />)
    const line = screen.getByText('Auction house prices scanned 5 min ago.')
    expect(line).not.toHaveStyle({ fontWeight: 500 })
    expect(line).toHaveAttribute('title', expect.stringMatching(/UTC$/))
  })

  it('warns when the scan is over an hour old', () => {
    renderWithProviders(<PriceFreshness lastScan={ago(61)} onUpload={vi.fn()} />)
    const line = screen.getByText('Auction house prices are from a scan 1 h ago.')
    expect(line).toHaveStyle({ fontWeight: 500 })
    expect(line.querySelector('svg')).toBeInTheDocument()
  })

  it('warns when there is no scan', () => {
    renderWithProviders(<PriceFreshness lastScan={null} onUpload={vi.fn()} />)
    const line = screen.getByText(/^Nobody has scanned this auction house yet\. At the auction house, press Alt Army scan/)
    expect(line).toHaveStyle({ fontWeight: 500 })
  })

  it('opens an upload', async () => {
    const onUpload = vi.fn()
    renderWithProviders(<PriceFreshness lastScan={ago(90)} onUpload={onUpload} />)
    const button = screen.getByRole('button', { name: 'Upload your scan' })
    await userEvent.click(button)
    expect(onUpload).toHaveBeenCalledOnce()
  })
})
