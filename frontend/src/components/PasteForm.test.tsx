import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { LINKED, mockApi, renderWithProviders } from '../test/utils'
import { PasteForm } from './PasteForm'

describe('PasteForm', () => {
  it('says the export brings characters only, not auction house scans', () => {
    renderWithProviders(<PasteForm onImported={vi.fn()} />, LINKED)
    expect(screen.getByRole('textbox', { name: 'Alt Army export' })).toHaveAccessibleDescription(
      /characters only, not auction house scans: upload AltArmy_TBC\.lua/,
    )
  })

  it("shows why a pasted export was refused, such as the other game's", async () => {
    const fetch = mockApi({})
    fetch.mockImplementation(async (request: Request) =>
      request.method === 'POST'
        ? new Response(JSON.stringify({ detail: 'This is a TBC Anniversary export: switch the game at the top.' }), {
            status: 400,
          })
        : new Response('[]', { status: 200 }),
    )
    const onImported = vi.fn()
    renderWithProviders(<PasteForm onImported={onImported} />, LINKED)
    expect(screen.getByRole('button', { name: 'Import characters' })).toBeDisabled()
    await userEvent.type(screen.getByRole('textbox', { name: 'Alt Army export' }), 'AAX1:abc')
    await userEvent.click(screen.getByRole('button', { name: 'Import characters' }))
    expect(await screen.findByText('This is a TBC Anniversary export: switch the game at the top.')).toBeInTheDocument()
    expect(onImported).not.toHaveBeenCalled()
  })
})
