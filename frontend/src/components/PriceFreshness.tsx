import { useState } from 'react'
import { Button, Group, Text } from '@mantine/core'
import { useInterval } from '@mantine/hooks'
import { age, parseUtc } from '../lib/age'
import { IconWarning } from './icons'

/** Prices older than this are called out: a scan since then would give better results. */
export const STALE_AFTER_MS = 60 * 60_000

/** How a scan is taken: prices come from the Alt Army addon's own scan of the auction house. */
export const HOW_TO_SCAN = 'At the auction house, press Alt Army scan, then upload your Alt Army data.'

/**
 * How fresh the selected auction house's prices are: when its newest scan was made, in a warning colour once
 * that is over an hour ago (or there is no scan at all), and the button that opens an upload of a newer scan (`onUpload`).
 */
export function PriceFreshness({
  lastScan,
  onUpload,
}: {
  lastScan: string | null
  onUpload: () => void
}) {
  // Re-render each minute, so the age keeps up while the page stays open.
  const [now, setNow] = useState(() => new Date())
  useInterval(() => setNow(new Date()), 60_000, { autoInvoke: true })
  const scanned = lastScan === null ? Number.NaN : parseUtc(lastScan)
  const stale = Number.isNaN(scanned) || now.getTime() - scanned > STALE_AFTER_MS
  const text =
    lastScan === null
      ? `Nobody has scanned this auction house yet. ${HOW_TO_SCAN}`
      : stale
        ? `Auction house prices are from a scan ${age(lastScan, now)}.`
        : `Auction house prices scanned ${age(lastScan, now)}.`
  return (
    <Group gap="sm" role="status" aria-label="Price freshness">
      <Text
        size="sm"
        fw={stale ? 500 : undefined}
        c={stale ? 'yellow' : 'dimmed'}
        title={lastScan ? `${lastScan} UTC` : undefined}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
      >
        {stale && <IconWarning size={16} />}
        {text}
      </Text>
      <Button size="compact-xs" variant="light" onClick={onUpload}>
        Upload your scan
      </Button>
    </Group>
  )
}
