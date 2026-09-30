import { useState } from 'react'
import { Alert, Badge, Button, Group, Stack, Text, Textarea } from '@mantine/core'
import type { UploadResult } from '../api/client'
import { usePasteUpload } from '../api/queries'

/** What an upload or paste brought in: the characters, and a line per auction house scan recorded. */
export function Summary({ result }: { result: UploadResult }) {
  return (
    <Stack gap={4}>
      {result.kind === 'altarmy' && (
        <Text size="sm">
          Uploaded {result.characters} characters
          {result.groups.length > 0 &&
            `: ${result.groups.map((g) => `${g.realm} (${g.faction || 'no faction'}) ${g.characters}`).join(', ')}`}
          .
        </Text>
      )}
      {result.kind !== 'altarmy' && !result.realms.length && <Text size="sm">No realm in the file has prices.</Text>}
      {result.realms.map((r, i) => (
        <Group key={`${r.key}-${i}`} gap="xs">
          <Text size="sm">
            {r.realm || r.key}
            {r.faction ? ` (${r.faction})` : ''} scan: {r.items.toLocaleString()} prices
            {r.quarantined ? '' : `, ${r.moved.toLocaleString()} changed`}
          </Text>
          {r.quarantined && (
            <Badge color="yellow" variant="light" title="They differ widely from recent scans of this realm">
              not used
            </Badge>
          )}
        </Group>
      ))}
    </Stack>
  )
}

/**
 * The Alt Army addon's export string: characters without a file or /reload (but no auction house scans).
 * `onImported` runs after a successful upload.
 */
export function PasteForm({ onImported, autoFocus }: { onImported: (r: UploadResult) => void; autoFocus?: boolean }) {
  const upload = usePasteUpload()
  const [text, setText] = useState('')
  return (
    <Stack gap="sm">
      <Textarea
        label="Alt Army export"
        description="It brings in your characters only, not auction house scans: upload AltArmy_TBC.lua for those."
        placeholder="AAX1:..."
        value={text}
        onChange={(e) => {
          setText(e.currentTarget.value)
          upload.reset()
        }}
        rows={3}
        autoFocus={autoFocus}
        styles={{ input: { fontFamily: 'var(--mantine-font-family-monospace)', wordBreak: 'break-all' } }}
      />
      <Group>
        <Button
          disabled={!text.trim()}
          loading={upload.isPending}
          onClick={() => upload.mutate(text, { onSuccess: onImported })}
        >
          Upload characters
        </Button>
      </Group>
      {upload.isError && <Alert color="red">{upload.error.message}</Alert>}
    </Stack>
  )
}
