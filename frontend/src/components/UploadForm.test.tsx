import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { components } from '../api/schema'
import { LINKED, mockApi, renderWithProviders } from '../test/utils'
import { UploadForm } from './UploadForm'

type UploadResult = components['schemas']['UploadResult']

const characters: UploadResult = {
  kind: 'altarmy',
  detail: '3 characters',
  characters: 3,
  groups: [
    { realm: 'Classic Beta PvE', faction: 'Horde', characters: 1 },
    { realm: 'Dreamscythe', faction: 'Horde', characters: 2 },
  ],
  realms: [],
}

/** Mantine's FileInput is a button over a hidden file input. */
const fileInput = () => document.querySelector<HTMLInputElement>('input[type="file"]')!

const form = <UploadForm kind="altarmy" name="AltArmy_TBC.lua" />

describe('UploadForm', () => {
  it('uploads a file for the game and shows what it imported', async () => {
    // Node's FormData (which Request needs) refuses jsdom's File on newer Node versions, so record what the
    // app appends and pass Node a placeholder.
    const appended = new Map<string, unknown>()
    vi.stubGlobal(
      'FormData',
      class extends FormData {
        override append(name: string, value: string | Blob, fileName?: string): void {
          appended.set(name, value)
          super.append(name, typeof value === 'string' ? value : `file ${fileName}`)
        }
      },
    )
    const fetch = mockApi({ '/api/uploads': characters })
    renderWithProviders(form, LINKED)
    const file = new File(['AltArmyTBC_Data = {}'], 'AltArmy_TBC.lua', { lastModified: 1_790_000_000_000 })
    expect(screen.getByRole('button', { name: 'AltArmy_TBC.lua for WoW: Forever' })).toBeInTheDocument()
    await userEvent.upload(fileInput(), file)
    await userEvent.click(screen.getByRole('button', { name: 'Upload' }))
    expect(await screen.findByText(/Imported 3 characters: Classic Beta PvE \(Horde\) 1, Dreamscythe \(Horde\) 2/)).toBeInTheDocument()

    const post = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'POST')
    expect(new URL(post!.url).searchParams.get('game_version')).toBe('forever')
    expect(appended.get('kind')).toBe('altarmy')
    expect(appended.get('modified_at')).toBe('1790000000000')
    expect(appended.get('file')).toBe(file)
  })

  it('shows why an upload was refused', async () => {
    const fetch = mockApi({})
    fetch.mockImplementation(async (request: Request) =>
      request.method === 'POST'
        ? new Response(JSON.stringify({ detail: 'no AltArmyTBC_Data in file' }), { status: 400 })
        : new Response('[]', { status: 200 }),
    )
    renderWithProviders(form, LINKED)
    await userEvent.upload(fileInput(), new File(['x'], 'AltArmy_TBC.lua'))
    await userEvent.click(screen.getByRole('button', { name: 'Upload' }))
    expect(await screen.findByText('no AltArmyTBC_Data in file')).toBeInTheDocument()
  })

  it('says what the scans in the file changed, and which were not used', async () => {
    const scans: UploadResult = {
      ...characters,
      realms: [
        { key: 'Classic Beta PvE Horde', auction_house_id: 1, realm: 'Classic Beta PvE', faction: 'Horde', items: 2778, moved: 0, quarantined: true },
        { key: 'Dreamscythe Horde', auction_house_id: 2, realm: 'Dreamscythe', faction: 'Horde', items: 5, moved: 2, quarantined: false },
      ],
    }
    mockApi({ '/api/uploads': scans })
    renderWithProviders(form, LINKED)
    await userEvent.upload(fileInput(), new File(['x'], 'AltArmy_TBC.lua'))
    await userEvent.click(screen.getByRole('button', { name: 'Upload' }))
    expect(await screen.findByText(/some prices were not used/)).toBeInTheDocument()
    expect(screen.getByText(/Imported 3 characters/)).toBeInTheDocument()
    expect(screen.getAllByText('not used')).toHaveLength(1)
    expect(screen.getByText(`Classic Beta PvE (Horde) scan: ${(2778).toLocaleString()} prices`)).toBeInTheDocument()
    expect(screen.getByText('Dreamscythe (Horde) scan: 5 prices, 2 changed')).toBeInTheDocument()
  })
})
