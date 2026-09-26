import { useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Flex,
  Group,
  Loader,
  MultiSelect,
  NumberInput,
  Select,
  SimpleGrid,
  Stack,
  Switch,
  Text,
} from '@mantine/core'
import { useDebouncedValue } from '@mantine/hooks'
import { z } from 'zod'
import {
  type Exit,
  type RankParams,
  useAhBlocked,
  useCharacters,
  useCoverage,
  useDataVersion,
  useProfessions,
  useRank,
  useSelectRealm,
  useSetAhBlocked,
  useStatus,
} from '../api/queries'
import { goldToCopper } from '../lib/money'
import { fromKey, realmOptions, toKey } from '../lib/realms'
import { useSession } from '../lib/session'
import { useStoredState } from '../lib/storage'
import { ResultsTable } from './ResultsTable'

/** Results per page: the first request asks for this many, and each "Show more" for this many more. */
const PAGE = 50

const EXITS: { value: Exit; label: string }[] = [
  { value: 'vendor', label: 'Vendor' },
  { value: 'disenchant', label: 'Disenchant' },
  { value: 'ah', label: 'Auction house' },
]
const ALL_EXITS: Exit[] = EXITS.map((e) => e.value)
const SECTIONS = ['advanced'] as const
const NONE_OPEN: string[] = []
const NO_PROFESSIONS: string[] = []

const bound = z.number().nullable()
/** NumberInput reports an empty field as ''; that means no bound. */
const toBound = (v: number | string) => (typeof v === 'number' ? v : null)
const scaled = (v: number | null, f: (v: number) => number) => (v === null ? null : f(v))

type Filters = Omit<RankParams, 'top'>

function Results({ filters, browsing }: { filters: Filters; browsing: boolean }) {
  // Back to one page whenever the filters change.
  const [page, setPage] = useState({ filters, top: PAGE })
  const top = page.filters === filters ? page.top : PAGE
  const rank = useRank({ ...filters, top })
  const version = useDataVersion()
  const ahBlockedList = useAhBlocked().data
  const ahBlocked = useMemo(() => new Set(ahBlockedList?.items.map((i) => i.item_id)), [ahBlockedList])
  const { mutate: setAhBlocked } = useSetAhBlocked()
  if (rank.isPending) return <Loader />
  if (rank.isError) return <Alert color="red">{rank.error.message}</Alert>
  const { results, total } = rank.data
  if (!results.length) {
    return (
      <Alert>
        {browsing
          ? 'No recipes match these filters with the current prices.'
          : 'No recipes match these filters for these characters with the current prices.'}
      </Alert>
    )
  }
  return (
    <Stack>
      <ResultsTable
        results={results}
        items={rank.data.items}
        classes={rank.data.classes}
        params={{
          includeUnlearned: filters.includeUnlearned,
          includeTrivial: filters.includeTrivial,
          exits: filters.exits,
          version,
        }}
        ahBlocked={ahBlocked}
        onSetAhBlocked={(itemId, blocked) => setAhBlocked({ itemId, blocked })}
      />
      {total > results.length && (
        <Group justify="center">
          <Text size="sm" c="dimmed">
            Showing {results.length} of {total}
          </Text>
          <Button
            variant="light"
            loading={rank.isPlaceholderData}
            onClick={() => setPage({ filters, top: top + PAGE })}
          >
            Show more
          </Button>
        </Group>
      )}
    </Stack>
  )
}

type RangeProps = {
  name: string // e.g. "cost (gold)"
  min: number | null
  max: number | null
  onMin: (v: number | null) => void
  onMax: (v: number | null) => void
  step: number
}

function Range({ name, min, max, onMin, onMax, step }: RangeProps) {
  return (
    <Group grow gap="xs" align="flex-start">
      <NumberInput
        label={`Min ${name}`}
        value={min ?? ''}
        onChange={(v) => onMin(toBound(v))}
        step={step}
        decimalScale={4}
      />
      <NumberInput
        label={`Max ${name}`}
        placeholder="No max"
        value={max ?? ''}
        onChange={(v) => onMax(toBound(v))}
        step={step}
        decimalScale={4}
      />
    </Group>
  )
}

export function SearchTab() {
  const status = useStatus()
  const { mode } = useSession()
  const characters = useCharacters()
  const coverage = useCoverage()
  const professionNames = useProfessions()
  const select = useSelectRealm()
  const [includeUnlearned, setIncludeUnlearned] = useStoredState(
    'altarmy-profit.search.includeUnlearned',
    z.boolean(),
    false,
  )
  const [includeTrivial, setIncludeTrivial] = useStoredState(
    'altarmy-profit.search.includeTrivial',
    z.boolean(),
    true,
  )
  // Stored as strings: sections that no longer exist (the old Characters one) are dropped, not an error.
  const [stored, setOpen] = useStoredState('altarmy-profit.search.open', z.array(z.string()), NONE_OPEN)
  const open = SECTIONS.filter((s) => stored.includes(s))
  const [exits, setExits] = useStoredState('altarmy-profit.search.exits', z.array(z.enum(ALL_EXITS)), ALL_EXITS)
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useStoredState('altarmy-profit.search.minCost', bound, 0)
  const [maxCost, setMaxCost] = useStoredState('altarmy-profit.search.maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useStoredState('altarmy-profit.search.minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useStoredState('altarmy-profit.search.maxProfit', bound, null)
  const [minRoi, setMinRoi] = useStoredState('altarmy-profit.search.minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useStoredState('altarmy-profit.search.maxRoi', bound, null)
  const [professions, setProfessions] = useStoredState(
    'altarmy-profit.search.professions',
    z.array(z.string()),
    NO_PROFESSIONS,
  )
  const filters = useMemo<Filters>(
    () => ({
      includeUnlearned,
      includeTrivial,
      exits: ALL_EXITS.filter((e) => exits.includes(e)),
      minCost: scaled(minCost, goldToCopper),
      maxCost: scaled(maxCost, goldToCopper),
      minProfit: scaled(minProfit, goldToCopper),
      maxProfit: scaled(maxProfit, goldToCopper),
      minRoi: scaled(minRoi, (p) => p / 100),
      maxRoi: scaled(maxRoi, (p) => p / 100),
      professions,
    }),
    [includeUnlearned, includeTrivial, exits, minCost, maxCost, minProfit, maxProfit, minRoi, maxRoi, professions],
  )
  const [debouncedFilters] = useDebouncedValue(filters, 300)

  if (status.isPending) return <Loader />
  if (status.isError) return <Alert color="red">{status.error.message}</Alert>
  if (status.data.recipes === 0) {
    return (
      <Alert color="red">
        No recipes in {status.data.db_path}. Download game data on the Manage page (or run `altarmy-profit ingest`).
      </Alert>
    )
  }

  const groups = characters.data?.groups ?? []
  // Show the realm being switched to while the server imports its prices.
  const selection = select.isPending ? select.variables : status.data.selection
  const group = groups.find((g) => selection && toKey(g) === toKey(selection))
  // Without characters on the selected realm, every recipe is ranked for one unnamed crafter.
  const browsing = group === undefined
  const options = realmOptions(groups, coverage.data ?? [])
  const grouped = (['Your characters', 'Browse a realm'] as const)
    .map((name) => ({
      group: name,
      items: options.filter((o) => o.section === name).map(({ value, label }) => ({ value, label })),
    }))
    .filter((g) => g.items.length > 0)
  if (selection && !options.some((o) => o.value === toKey(selection))) {
    // e.g. a realm whose scan is still being merged: still show what is selected
    grouped.push({ group: 'Browse a realm', items: [{ value: toKey(selection), label: selection.realm }] })
  }

  return (
    <Stack>
      {status.data.warnings.map((w) => (
        <Alert key={w} color="yellow">
          {w}
        </Alert>
      ))}
      <Flex
        direction={{ base: 'column', sm: 'row' }}
        justify="space-between"
        align={{ base: 'stretch', sm: 'flex-end' }}
        gap="md"
      >
        <Select
          label="Realm and faction"
          placeholder="No realm has prices yet"
          data={grouped}
          value={selection ? toKey(selection) : null}
          onChange={(key) => key && select.mutate(fromKey(key))}
          allowDeselect={false}
          style={{ flex: 1, maxWidth: 420 }}
        />
        <MultiSelect
          label="Professions"
          placeholder={professions.length ? undefined : 'Every profession'}
          data={professionNames.data ?? []}
          value={professions}
          onChange={setProfessions}
          clearable
          searchable
          style={{ flex: 1, maxWidth: 420 }}
        />
        {!browsing && (
          <Switch
            label="Include recipes not learned yet"
            description="Every recipe of these characters' professions, not just the ones they know."
            checked={includeUnlearned}
            onChange={(e) => setIncludeUnlearned(e.currentTarget.checked)}
          />
        )}
      </Flex>
      {browsing && (
        <Text size="sm" c="dimmed">
          Browsing every recipe on this realm, crafted and sold by one character. Add your characters to see who can
          craft what and what mailing between them costs.
        </Text>
      )}
      <Accordion
        multiple
        variant="separated"
        value={open}
        onChange={(v) => setOpen(SECTIONS.filter((s) => v.includes(s)))}
      >
        <Accordion.Item value="advanced">
          <Accordion.Control>Advanced Options</Accordion.Control>
          <Accordion.Panel>
            <Stack>
              {!browsing && (
                <Checkbox
                  label="Include Trivial Recipes"
                  description="Uncheck to show only recipes that can still give the crafter a skill point."
                  checked={includeTrivial}
                  onChange={(e) => setIncludeTrivial(e.currentTarget.checked)}
                />
              )}
              <Checkbox.Group
                label="Sell via"
                value={exits}
                onChange={(v) => setExits(ALL_EXITS.filter((e) => v.includes(e)))}
              >
                <Group mt={4}>
                  {EXITS.map((e) => (
                    <Checkbox key={e.value} value={e.value} label={e.label} />
                  ))}
                </Group>
              </Checkbox.Group>
              <SimpleGrid cols={{ base: 1, sm: 3 }}>
                <Range
                  name="cost (gold)"
                  min={minCost}
                  max={maxCost}
                  onMin={setMinCost}
                  onMax={setMaxCost}
                  step={1}
                />
                <Range
                  name="profit (gold)"
                  min={minProfit}
                  max={maxProfit}
                  onMin={setMinProfit}
                  onMax={setMaxProfit}
                  step={0.5}
                />
                <Range name="ROI (%)" min={minRoi} max={maxRoi} onMin={setMinRoi} onMax={setMaxRoi} step={10} />
              </SimpleGrid>
            </Stack>
          </Accordion.Panel>
        </Accordion.Item>
      </Accordion>
      {status.data.prices === 0 && (
        <Alert color="yellow">
          {mode === 'hosted'
            ? 'No prices yet for this realm. Scan the auction house with Auctionator, then upload Auctionator.lua on the Upload page.'
            : 'No prices yet. Scan the auction house with Auctionator, then /reload.'}
        </Alert>
      )}
      {debouncedFilters.exits.length ? (
        <Results filters={debouncedFilters} browsing={browsing} />
      ) : (
        <Alert>Pick at least one way to sell under Advanced Options.</Alert>
      )}
    </Stack>
  )
}
