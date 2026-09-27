import type { ReactNode } from 'react'
import { Alert, Badge, Card, Group, Loader, Stack, Table, Text, Title } from '@mantine/core'
import type { Ingestion } from '../api/client'
import { useAdminIngestion } from '../api/queries'
import { age, parseUtc } from '../lib/age'

type Job = Ingestion['jobs'][number]
type Run = Ingestion['runs'][number]

const JOB_NAMES: Readonly<Record<string, string>> = {
  ingest: 'Game data ingest',
  merge: 'Price merge',
  prune: 'Prune',
  ahledger: 'AHledger poll',
}

/** When a server timestamp was, relative to the server's `now`, with the exact UTC time on hover. */
function When({ utc, now }: { utc: string | null; now: Date }) {
  if (!utc) return <Text span c="dimmed">never</Text>
  return <span title={`${utc} UTC`}>{age(utc, now)}</span>
}

function RunBadge({ ok, finished }: { ok: boolean | null; finished: string | null }) {
  if (ok === true) return <Badge color="green" variant="light">ok</Badge>
  if (ok === false) return <Badge color="red" variant="light">failed</Badge>
  return finished === null ? <Badge color="yellow" variant="light">running</Badge> : null
}

/** The summary's last line (where failures are), with the whole of it on hover. */
function Summary({ text }: { text: string }) {
  const last = text.trim().split('\n').at(-1) ?? ''
  return (
    <Text size="sm" title={text || undefined} lineClamp={2}>
      {last}
    </Text>
  )
}

function Section({ title, lead, children }: { title: string; lead?: ReactNode; children: ReactNode }) {
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>{title}</Title>
        {lead && (
          <Text size="sm" c="dimmed">
            {lead}
          </Text>
        )}
        <Table.ScrollContainer minWidth={560}>{children}</Table.ScrollContainer>
      </Stack>
    </Card>
  )
}

function JobsCard({ jobs, now }: { jobs: readonly Job[]; now: Date }) {
  return (
    <Section title="Jobs" lead="Each scheduled job's newest run. Late: it has not run for twice its schedule.">
      <Table aria-label="Jobs">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Job</Table.Th>
            <Table.Th>Last run</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Said</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {jobs.map((j) => (
            <Table.Tr key={j.job}>
              <Table.Td>{JOB_NAMES[j.job] ?? j.job}</Table.Td>
              <Table.Td>
                <When utc={j.last_started} now={now} />
              </Table.Td>
              <Table.Td>
                <Group gap={4} wrap="nowrap">
                  <RunBadge ok={j.ok} finished={j.last_finished} />
                  {j.late && (
                    <Badge color="red" variant="outline">
                      late
                    </Badge>
                  )}
                </Group>
              </Table.Td>
              <Table.Td>
                <Summary text={j.summary} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function duration(run: Run): string {
  if (!run.finished_at) return ''
  const seconds = Math.round((parseUtc(run.finished_at) - parseUtc(run.started_at)) / 1000)
  return seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 60)} min`
}

function RunsCard({ runs, now }: { runs: readonly Run[]; now: Date }) {
  if (!runs.length) return null
  return (
    <Section title="Recent runs">
      <Table aria-label="Recent runs">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Started</Table.Th>
            <Table.Th>Job</Table.Th>
            <Table.Th>Took</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Said</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {runs.map((r) => (
            <Table.Tr key={r.id}>
              <Table.Td>
                <When utc={r.started_at} now={now} />
              </Table.Td>
              <Table.Td>
                {JOB_NAMES[r.job] ?? r.job}
                {r.game_version ? ` (${r.game_version})` : ''}
              </Table.Td>
              <Table.Td>{duration(r)}</Table.Td>
              <Table.Td>
                <RunBadge ok={r.ok} finished={r.finished_at} />
              </Table.Td>
              <Table.Td>
                <Summary text={r.summary} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function UploadsCard({ uploads, now }: { uploads: Ingestion['uploads']; now: Date }) {
  const lead =
    `Last 24 hours: ${uploads.accepted_24h} accepted, ${uploads.rejected_24h} rejected. ` +
    `Last 7 days: ${uploads.accepted_7d} accepted, ${uploads.rejected_7d} rejected, from ${uploads.uploaders_7d} users.`
  return (
    <Section title="Uploads" lead={lead}>
      <Table aria-label="Uploads">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Received</Table.Th>
            <Table.Th>User</Table.Th>
            <Table.Th>File</Table.Th>
            <Table.Th>Outcome</Table.Th>
            <Table.Th>Detail</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {uploads.recent.map((u) => (
            <Table.Tr key={u.id}>
              <Table.Td>
                <When utc={u.received_at} now={now} />
              </Table.Td>
              <Table.Td>
                <Text size="sm" ff="monospace" title={u.user_uid}>
                  {u.user_uid.slice(0, 8)}
                </Text>
              </Table.Td>
              <Table.Td>
                {u.kind} ({u.via}, {Math.ceil(u.size / 1024).toLocaleString()} KB)
              </Table.Td>
              <Table.Td>
                <Badge color={u.outcome === 'accepted' ? 'green' : 'red'} variant="light">
                  {u.outcome}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Text size="sm" lineClamp={2} title={u.detail}>
                  {u.detail}
                </Text>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function SnapshotsCard({ snapshots, now }: { snapshots: Ingestion['snapshots']; now: Date }) {
  return (
    <Section title="Price snapshots" lead="Scans recorded in the last 7 days, per source.">
      <Table aria-label="Price snapshots">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Source</Table.Th>
            <Table.Th ta="right">24 hours</Table.Th>
            <Table.Th ta="right">7 days</Table.Th>
            <Table.Th ta="right">Not used (7 days)</Table.Th>
            <Table.Th ta="right">Items (7 days)</Table.Th>
            <Table.Th>Newest</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {snapshots.map((s) => (
            <Table.Tr key={s.source}>
              <Table.Td>{s.source}</Table.Td>
              <Table.Td ta="right">{s.snapshots_24h}</Table.Td>
              <Table.Td ta="right">{s.snapshots_7d}</Table.Td>
              <Table.Td ta="right">{s.quarantined_7d}</Table.Td>
              <Table.Td ta="right">{s.items_7d.toLocaleString()}</Table.Td>
              <Table.Td>
                <When utc={s.newest_received_at} now={now} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function FeedsCard({ feeds, now }: { feeds: Ingestion['feeds']; now: Date }) {
  if (!feeds.length) return null
  return (
    <Section title="AHledger feeds" lead="Each market's newest table. A poll that finds no newer table leaves it.">
      <Table aria-label="AHledger feeds">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Market</Table.Th>
            <Table.Th>Auction house</Table.Th>
            <Table.Th ta="right">Items</Table.Th>
            <Table.Th>Scanned</Table.Th>
            <Table.Th>Fetched</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {feeds.map((f) => (
            <Table.Tr key={f.market}>
              <Table.Td>{f.market}</Table.Td>
              <Table.Td>
                {f.realm} ({f.faction})
              </Table.Td>
              <Table.Td ta="right">{f.rows.toLocaleString()}</Table.Td>
              <Table.Td>
                <When utc={f.scanned_at} now={now} />
              </Table.Td>
              <Table.Td>
                <When utc={f.fetched_at} now={now} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

/** The ingestion log and statistics: jobs, their runs, every user's uploads, snapshots per source, feeds. */
export function AdminTab() {
  const ingestion = useAdminIngestion(true)
  if (ingestion.isPending) return <Loader aria-label="Loading" />
  if (ingestion.isError) return <Alert color="red">{ingestion.error.message}</Alert>
  const data = ingestion.data
  const now = new Date(parseUtc(data.now))
  return (
    <Stack gap="lg">
      <JobsCard jobs={data.jobs} now={now} />
      <RunsCard runs={data.runs} now={now} />
      <UploadsCard uploads={data.uploads} now={now} />
      <SnapshotsCard snapshots={data.snapshots} now={now} />
      <FeedsCard feeds={data.feeds} now={now} />
    </Stack>
  )
}
