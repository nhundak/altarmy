import { useState } from 'react'
import { Alert, Badge, Button, Group, Stack, Text, Textarea } from '@mantine/core'
import type { UploadResult } from '../api/client'
import { usePasteUpload } from '../api/queries'

/** What an upload or paste brought in, in a sentence per realm. */
export function Summary({ result }: { result: UploadResult }) {
  if (result.kind === 'altarmy') {
    return (
      <Text size="sm">
        Imported {result.characters} characters
        {result.groups.length > 0 &&
          `: ${result.groups.map((g) => `${g.realm} (${g.faction || 'no faction'}) ${g.characters}`).join(', ')}`}
        .
      </Text>
    )
  }
  if (!result.realms.length) return <Text size="sm">No realm in the file has prices.</Text>
  return (
    <Stack gap={4}>
      {result.realms.map((r) => (
        <Group key={r.key} gap="xs">
          <Text size="sm">
            {r.realm}
            {r.faction ? ` (${r.faction})` : ''}: {r.items} prices
            {r.quarantined ? '' : `, ${r.moved} changed`}
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
 * The Alt Army addon's export string: characters without a file or /reload. `onImported` runs after a successful
 * import; without it the form shows what was imported.
 */
export function PasteForm({ onImported, autoFocus }: { onImported?: (r: UploadResult) => void; autoFocus?: boolean }) {
  const upload = usePasteUpload()
  const [text, setText] = useState('')
  return (
    <Stack gap="sm">
      <Textarea
        label="Alt Army export"
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
          onClick={() => upload.mutate(text, { onSuccess: (r) => onImported?.(r) })}
        >
          Import characters
        </Button>
      </Group>
      {upload.isError && <Alert color="red">{upload.error.message}</Alert>}
      {upload.data && !onImported && (
        <Alert color="green" title="Imported">
          <Summary result={upload.data} />
        </Alert>
      )}
    </Stack>
  )
}
