import { screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Ingestion } from '../api/client'
import { mockApi, renderWithProviders } from '../test/utils'
import { AdminTab } from './AdminTab'

export const ingestion: Ingestion = {
  now: '2026-09-27 12:00:00',
  jobs: [
    {
      job: 'ingest',
      game_version: null,
      last_started: null,
      last_finished: null,
      ok: null,
      late: true,
      summary: '',
    },
    {
      job: 'merge',
      game_version: null,
      last_started: '2026-09-27 11:30:00',
      last_finished: '2026-09-27 11:30:40',
      ok: true,
      late: false,
      summary: 'Merged 3 auction houses of every game version (1 changed); 90 price observations stored.',
    },
    {
      job: 'prune',
      game_version: null,
      last_started: '2026-09-27 11:59:00',
      last_finished: null,
      ok: null,
      late: false,
      summary: '',
    },
    {
      job: 'ahledger',
      game_version: null,
      last_started: '2026-09-27 11:20:00',
      last_finished: '2026-09-27 11:21:00',
      ok: false,
      late: false,
      summary: 'forever.normal.horde.us: 12 items\n1 of 4 AHledger markets failed.',
    },
  ],
  runs: [
    {
      id: 7,
      job: 'merge',
      game_version: null,
      started_at: '2026-09-27 11:30:00',
      finished_at: '2026-09-27 11:30:40',
      ok: true,
      summary: 'Merged 3 auction houses',
    },
  ],
  uploads: {
    accepted_24h: 4,
    rejected_24h: 1,
    accepted_7d: 20,
    rejected_7d: 2,
    uploaders_7d: 3,
    recent: [
      {
        id: 1,
        game_version: 'forever',
        kind: 'auctionator',
        via: 'watcher',
        size: 2048,
        received_at: '2026-09-27 10:00:00',
        outcome: 'rejected',
        detail: 'Not an Auctionator file',
        user_uid: 'abcdefghijklmnop',
      },
    ],
  },
  snapshots: [
    {
      source: 'auctionator',
      snapshots_24h: 2,
      snapshots_7d: 9,
      quarantined_7d: 1,
      items_7d: 12345,
      newest_received_at: '2026-09-27 10:00:00',
    },
  ],
  feeds: [
    {
      market: 'forever.normal.horde.us',
      realm: 'Classic Beta PvE',
      faction: 'Horde',
      rows: 800,
      scanned_at: '2026-09-27 11:00:00',
      fetched_at: '2026-09-27 11:20:00',
    },
  ],
}

describe('AdminTab', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('shows each job with its status, lateness and last words', async () => {
    mockApi({ '/api/admin/ingestion': ingestion })
    renderWithProviders(<AdminTab />)
    const jobs = await screen.findByRole('table', { name: 'Jobs' })
    const rows = within(jobs).getAllByRole('row').slice(1)
    expect(rows.map((r) => within(r).getAllByRole('cell')[0]?.textContent)).toEqual([
      'Game data ingest',
      'Price merge',
      'Prune',
      'AHledger poll',
    ])
    const [ingest, merge, prune, ahledger] = rows.map((r) => within(r))
    expect(ingest?.getByText('never')).toBeInTheDocument()
    expect(ingest?.getByText('late')).toBeInTheDocument()
    expect(ingest?.queryByText('running')).not.toBeInTheDocument()
    expect(merge?.getByText('ok')).toBeInTheDocument()
    expect(merge?.getByText('30 min ago')).toHaveAttribute('title', '2026-09-27 11:30:00 UTC')
    expect(prune?.getByText('running')).toBeInTheDocument()
    expect(ahledger?.getByText('failed')).toBeInTheDocument()
    expect(ahledger?.getByText('1 of 4 AHledger markets failed.')).toBeInTheDocument()
  })

  it('shows the runs, uploads, snapshots and feeds', async () => {
    mockApi({ '/api/admin/ingestion': ingestion })
    renderWithProviders(<AdminTab />)
    const runs = await screen.findByRole('table', { name: 'Recent runs' })
    expect(within(runs).getByText('40 s')).toBeInTheDocument()
    expect(screen.getByText(/Last 24 hours: 4 accepted, 1 rejected\. Last 7 days: 20 accepted, 2 rejected, from 3 users\./)).toBeInTheDocument()
    const uploads = screen.getByRole('table', { name: 'Uploads' })
    expect(within(uploads).getByText('abcdefgh')).toHaveAttribute('title', 'abcdefghijklmnop')
    expect(within(uploads).getByText('rejected')).toBeInTheDocument()
    expect(within(screen.getByRole('table', { name: 'Price snapshots' })).getByText((12345).toLocaleString())).toBeInTheDocument()
    expect(within(screen.getByRole('table', { name: 'AHledger feeds' })).getByText('Classic Beta PvE (Horde)')).toBeInTheDocument()
  })

  it('says what went wrong', async () => {
    mockApi({})
    renderWithProviders(<AdminTab />)
    expect(await screen.findByText('no mock for /api/admin/ingestion')).toBeInTheDocument()
  })
})
