import { useState } from 'react'
import { Alert, Badge, Button, Card, Code, FileInput, Group, List, Stack, Table, Text, Title } from '@mantine/core'
import { useCoverage, useUpload, useUploads, type UploadKind } from '../api/queries'
import { age } from '../lib/age'
import { GAME_FLAVOR, GAME_VERSION_LABEL } from '../lib/gameVersion'
import { PasteForm, Summary } from './PasteForm'

const MAX_MB = 32

const FILES: readonly { kind: UploadKind; name: string; what: string }[] = [
  {
    kind: 'altarmy',
    name: 'AltArmy_TBC.lua',
    what: 'your characters, professions and learned recipes, and the auction house scans you took with Alt Army',
  },
]

/** How prices get here: the Alt Army addon's own scan of the auction house. */
function ScanCard() {
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>Scan the auction house</Title>
        <Text size="sm" c="dimmed">
          Prices come from scans taken with the Alt Army addon. A scan reads every listing, so a craft is priced
          from how many units are listed at each price, not from one listing.
        </Text>
        <List size="sm" type="ordered">
          <List.Item>
            At the auction house, press <b>Alt Army scan</b> (or type <Code>/altarmy scan</Code>) and keep the
            window open until it finishes.
          </List.Item>
          <List.Item>
            Log out or type <Code>/reload</Code>, so WoW writes the scan to AltArmy_TBC.lua.
          </List.Item>
          <List.Item>Upload AltArmy_TBC.lua below, or let Alt Army Sync send it for you.</List.Item>
        </List>
        <Text size="sm" c="dimmed">
          The game allows one full scan every 15 minutes. The Alt Army export string carries characters only, not
          scans.
        </Text>
      </Stack>
    </Card>
  )
}

/** The Alt Army addon's export string: characters without a file or /reload. */
function PasteCard() {
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>Paste from Alt Army</Title>
        <Text size="sm" c="dimmed">
          The quickest way to bring in your characters: in game, type <Code>/altarmy export</Code>, press Ctrl+C,
          and paste the string here. No logout or /reload needed.
        </Text>
        <PasteForm />
      </Stack>
    </Card>
  )
}

/** Each realm's newest scan, stalest first: where uploads are needed. */
function CoverageCard() {
  const coverage = useCoverage()
  if (!coverage.data?.length) return null
  const stalest = [...coverage.data].sort((a, b) => (a.last_scan ?? '').localeCompare(b.last_scan ?? ''))
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>Coverage</Title>
        <Text size="sm" c="dimmed">
          Every user's scans price these auction houses. The stalest come first: a scan there helps the most.
        </Text>
        <Table aria-label="Coverage">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Realm</Table.Th>
              <Table.Th>Last scan</Table.Th>
              <Table.Th ta="right">Items in it</Table.Th>
              <Table.Th ta="right">Prices</Table.Th>
              <Table.Th ta="right">Scans (7 days)</Table.Th>
              <Table.Th ta="right">Uploaders (7 days)</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {stalest.map((c) => (
              <Table.Tr key={c.auction_house_id}>
                <Table.Td>
                  {c.realm}
                  {c.faction ? ` (${c.faction})` : ''}
                </Table.Td>
                <Table.Td title={c.last_scan ? `${c.last_scan} UTC` : undefined}>
                  {c.last_scan ? age(c.last_scan) : 'never'}
                </Table.Td>
                <Table.Td ta="right">{c.last_scan_items.toLocaleString()}</Table.Td>
                <Table.Td ta="right">{c.prices.toLocaleString()}</Table.Td>
                <Table.Td ta="right">{c.scans_7d}</Table.Td>
                <Table.Td ta="right">{c.uploaders_7d}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Stack>
    </Card>
  )
}

function uploadedTitle(realms: readonly { quarantined: boolean }[]): string {
  if (realms.some((r) => r.quarantined)) return 'Uploaded, but some prices were not used: they differ widely from recent scans'
  return 'Uploaded'
}

function UploadCard({ kind, name, what }: { kind: UploadKind; name: string; what: string }) {
  const upload = useUpload()
  const [file, setFile] = useState<File | null>(null)
  const tooBig = file !== null && file.size > MAX_MB * 2 ** 20
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>{name}</Title>
        <Text size="sm" c="dimmed">
          Brings in {what}. It is in{' '}
          <Code>
            World of Warcraft\{GAME_FLAVOR}\WTF\Account\&lt;account&gt;\SavedVariables\{name}
          </Code>
          ; WoW writes it on logout or /reload.
        </Text>
        <Group align="flex-end">
          <FileInput
            label={`${name} for ${GAME_VERSION_LABEL}`}
            placeholder={`Pick ${name}`}
            accept=".lua"
            value={file}
            onChange={(f) => {
              setFile(f)
              upload.reset()
            }}
            clearable
            w={360}
          />
          <Button disabled={!file || tooBig} loading={upload.isPending} onClick={() => file && upload.mutate({ kind, file })}>
            Upload
          </Button>
        </Group>
        {tooBig && <Alert color="red">Files are limited to {MAX_MB} MB.</Alert>}
        {upload.isError && <Alert color="red">{upload.error.message}</Alert>}
        {upload.data && (
          <Alert
            color={upload.data.realms.some((r) => r.quarantined) ? 'yellow' : 'green'}
            title={uploadedTitle(upload.data.realms)}
          >
            <Summary result={upload.data} />
          </Alert>
        )}
      </Stack>
    </Card>
  )
}

function History() {
  const uploads = useUploads()
  if (!uploads.data?.length) return null
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>Your recent uploads</Title>
        <Table>
          <Table.Tbody>
            {uploads.data.map((u) => (
              <Table.Tr key={u.id}>
                <Table.Td>{u.received_at} UTC</Table.Td>
                <Table.Td>
                  {u.via === 'paste' ? 'Alt Army export' : u.kind === 'altarmy' ? 'AltArmy_TBC.lua' : 'Auctionator.lua'} ({u.game_version}, {u.via})
                </Table.Td>
                <Table.Td>
                  <Badge color={u.outcome === 'accepted' ? 'green' : 'red'} variant="light">
                    {u.outcome}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Text size="sm">{u.detail}</Text>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Stack>
    </Card>
  )
}

/** The way in for addon data: upload the SavedVariables file (or run Alt Army Sync, see Manage). */
export function UploadTab() {
  return (
    <Stack>
      <ScanCard />
      <PasteCard />
      {FILES.map((f) => (
        <UploadCard key={f.kind} {...f} />
      ))}
      <History />
      <CoverageCard />
    </Stack>
  )
}
