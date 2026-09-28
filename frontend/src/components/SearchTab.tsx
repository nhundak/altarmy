import { memo, useEffect, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Flex,
  Group,
  Loader,
  NumberInput,
  Radio,
  Select,
  SimpleGrid,
  Stack,
  Text,
} from '@mantine/core'
import { z } from 'zod'
import {
  type Exit,
  type RankParams,
  type Unlearned,
  useAhBlocked,
  useCharacters,
  useCoverage,
  useDataVersion,
  useFavorites,
  useRank,
  useSelectRealm,
  useSetAhBlocked,
  useSetFavorite,
  useStatus,
} from '../api/queries'
import { GOAL_SEARCH, goalSchema, type Goal } from '../lib/goals'
import { goldToCopper } from '../lib/money'
import { fromKey, realmOptions, toKey } from '../lib/realms'
import { useSession } from '../lib/session'
import { useStoredState } from '../lib/storage'
import { GoalPicker } from './GoalPicker'
import { PriceFreshness } from './PriceFreshness'
import { PriceSignal } from './PriceSignal'
import { ResultsTable } from './ResultsTable'
import { TimeSettingsPanel } from './TimeSettingsPanel'

/** Results per page: the first request asks for this many, and each "Show more" for this many more. */
const PAGE = 50

const EXITS: { value: Exit; label: string; description: string }[] = [
  { value: 'vendor', label: 'Vendor', description: "Rarely the best profit, but it's always available." },
  {
    value: 'disenchant',
    label: 'Disenchant',
    description:
      'Often the best choice if you want reliable results. Enchanting materials tend to have stable prices and sell well. Requires at least one character with enchanting',
  },
  {
    value: 'ah',
    label: 'Auction house',
    description:
      "Sometimes the best profit, but for some items there will be no buyers. You'll need to take an active role in figuring out what sells reliably.",
  },
]
const ALL_EXITS: Exit[] = EXITS.map((e) => e.value)
const UNLEARNED: { value: Unlearned; label: string }[] = [
  { value: 'none', label: 'Show recipes I already know' },
  { value: 'soon', label: 'Include recipes I can train soon (20 skill points)' },
  { value: 'all', label: 'Include all recipes' },
]
const SECTIONS = ['advanced', 'time'] as const
const NONE_OPEN: string[] = []
const storedGoal = goalSchema.nullable()

const bound = z.number().nullable()
/** NumberInput reports an empty field as ''; that means no bound. */
const toBound = (v: number | string) => (typeof v === 'number' ? v : null)
const scaled = (v: number | null, f: (v: number) => number) => (v === null ? null : f(v))

type Filters = Omit<RankParams, 'top'>

/**
 * `value` once it has stopped changing for `wait` ms (typing a bound re-ranks once, not per key), except that a new
 * `flush` (a goal just picked) takes it at once, so the results never show a request with the old goal's filters.
 */
function useSettled<T>(value: T, wait: number, flush: number): T {
  const [settled, setSettled] = useState({ value, flush })
  const flushing = settled.flush !== flush
  if (flushing) setSettled({ value, flush })
  useEffect(() => {
    // A timer already queued before the flush must not bring the older value back after it.
    const timer = setTimeout(() => setSettled((prev) => (prev.flush === flush ? { value, flush } : prev)), wait)
    return () => clearTimeout(timer)
  }, [value, wait, flush])
  return flushing ? value : settled.value
}

/** Memoized: opening or closing a filter section re-renders the search, and the table is the costly part. */
const Results = memo(function Results({
  filters,
  browsing,
}: {
  filters: Filters
  browsing: boolean
}) {
  // Back to one page whenever the filters change.
  const [page, setPage] = useState({ filters, top: PAGE })
  const top = page.filters === filters ? page.top : PAGE
  const rank = useRank({ ...filters, top })
  const version = useDataVersion()
  const ahBlockedList = useAhBlocked().data
  const ahBlocked = useMemo(() => new Set(ahBlockedList?.items.map((i) => i.item_id)), [ahBlockedList])
  const { mutate: setAhBlocked } = useSetAhBlocked()
  const favoriteList = useFavorites().data
  const favorites = useMemo(() => new Set(favoriteList?.recipes.map((f) => f.recipe_id)), [favoriteList])
  const { mutate: setFavorite } = useSetFavorite()
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
          unlearned: filters.unlearned,
          includeTrivial: filters.includeTrivial,
          exits: filters.exits,
          version,
        }}
        ahBlocked={ahBlocked}
        onSetAhBlocked={(itemId, blocked) => setAhBlocked({ itemId, blocked })}
        favorites={favorites}
        onSetFavorite={(recipeId, favorite) => setFavorite({ recipeId, favorite })}
        rankBy={filters.sort}
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
})

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

/**
 * The search: first the user's goal, then (once one is picked) the realm and faction, and with a realm the price
 * freshness, filters, time assumptions and ranked recipes. The goal decides the ranking's order and presets the filters
 * it cares about; it is remembered per user, like the Profit page's start.
 */
export function SearchTab() {
  const { uid } = useSession()
  const status = useStatus()
  const characters = useCharacters()
  const coverage = useCoverage()
  const select = useSelectRealm()
  const [savedGoal, setGoal] = useStoredState<Goal | null>(`altarmy-profit.goal.${uid}`, storedGoal, null)
  // Skilling up needs the characters' professions: without imported characters that goal can't be picked (and a
  // saved one asks again).
  const noCharacters = characters.data !== undefined && characters.data.groups.length === 0
  const goal = noCharacters && savedGoal === 'skill' ? null : savedGoal
  const [choosing, setChoosing] = useState(false)
  const [unlearned, setUnlearned] = useStoredState<Unlearned>(
    'altarmy-profit.search.unlearned',
    z.enum(['none', 'soon', 'all']),
    'none',
  )
  const [includeTrivial, setIncludeTrivial] = useStoredState(
    'altarmy-profit.search.includeTrivial',
    z.boolean(),
    true,
  )
  // Stored as strings: sections that no longer exist (the old Characters one) are dropped, not an error.
  const [stored, setOpen] = useStoredState('altarmy-profit.search.open', z.array(z.string()), NONE_OPEN)
  const open = SECTIONS.filter((s) => stored.includes(s))
  /** Open or close one section from its own accordion's value, keeping the other's state. */
  const toggleSection = (section: (typeof SECTIONS)[number], value: string[]) =>
    setOpen(SECTIONS.filter((s) => (s === section ? value.includes(s) : open.includes(s))))
  const [exits, setExits] = useStoredState('altarmy-profit.search.exits', z.array(z.enum(ALL_EXITS)), ALL_EXITS)
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useStoredState('altarmy-profit.search.minCost', bound, 0)
  const [maxCost, setMaxCost] = useStoredState('altarmy-profit.search.maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useStoredState('altarmy-profit.search.minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useStoredState('altarmy-profit.search.maxProfit', bound, null)
  const [minRoi, setMinRoi] = useStoredState('altarmy-profit.search.minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useStoredState('altarmy-profit.search.maxRoi', bound, null)
  const filters = useMemo<Filters>(
    () => ({
      unlearned,
      includeTrivial,
      exits: ALL_EXITS.filter((e) => exits.includes(e)),
      minCost: scaled(minCost, goldToCopper),
      maxCost: scaled(maxCost, goldToCopper),
      minProfit: scaled(minProfit, goldToCopper),
      maxProfit: scaled(maxProfit, goldToCopper),
      minRoi: scaled(minRoi, (p) => p / 100),
      maxRoi: scaled(maxRoi, (p) => p / 100),
      sort: goal ? GOAL_SEARCH[goal].sort : 'profit',
    }),
    [unlearned, includeTrivial, exits, minCost, maxCost, minProfit, maxProfit, minRoi, maxRoi, goal],
  )
  const [picks, setPicks] = useState(0)
  const debouncedFilters = useSettled(filters, 300, picks)

  /** Choose a goal, writing the filters it presets (the user may change them afterwards). */
  const pickGoal = (next: Goal) => {
    setGoal(next)
    setChoosing(false)
    setPicks((n) => n + 1)
    setIncludeTrivial(GOAL_SEARCH[next].includeTrivial)
    setMinProfit(GOAL_SEARCH[next].minProfit)
  }

  if (status.isPending) return <Loader />
  if (status.isError) return <Alert color="red">{status.error.message}</Alert>
  if (status.data.recipes === 0) {
    return (
      <Alert color="red">
        No game data has been loaded yet. If you run this site, run `altarmy-profit ingest`.
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
  // The selection's auction house and its newest scan; undefined while the coverage is still loading.
  const house = coverage.data?.find((c) => c.auction_house_id === status.data.auction_house_id)
  const lastScan = coverage.data && status.data.auction_house_id !== null ? (house?.last_scan ?? null) : undefined

  return (
    <Stack>
      <PriceSignal />
      <GoalPicker
        goal={goal}
        choosing={choosing}
        onPick={pickGoal}
        onChange={() => setChoosing(true)}
        unavailable={noCharacters ? { skill: 'Import your characters first, so we know which skills they have.' } : {}}
      />
      {goal !== null && !choosing && (
        <>
          <Flex
            direction={{ base: 'column', sm: 'row' }}
            justify="space-between"
            align={{ base: 'stretch', sm: 'flex-start' }}
            gap="md"
          >
            <Stack gap="xs" style={{ flex: 1 }}>
              <Select
                label="Realm and faction"
                placeholder="No realm has prices yet"
                data={grouped}
                value={selection ? toKey(selection) : null}
                onChange={(key) => key && select.mutate(fromKey(key))}
                allowDeselect={false}
                style={{ maxWidth: 420 }}
              />
              {selection && lastScan !== undefined && (
                <PriceFreshness lastScan={lastScan} ahledger={house?.sources.includes('ahledger')} />
              )}
            </Stack>
            {!browsing && (
              <Radio.Group
                label="Recipes"
                value={unlearned}
                onChange={(v) => setUnlearned(UNLEARNED.find((o) => o.value === v)?.value ?? 'none')}
              >
                <Stack mt={4} gap="xs">
                  {UNLEARNED.map((o) => (
                    <Radio key={o.value} value={o.value} label={o.label} />
                  ))}
                </Stack>
              </Radio.Group>
            )}
          </Flex>
          {selection && (
            <>
              {browsing && (
                <Text size="sm" c="dimmed">
                  Browsing every recipe on this realm, crafted and sold by one character. Add your characters to see
                  who can craft what and what mailing between them costs.
                </Text>
              )}
            {/* Two independent sections, side by side on large screens, each remembering whether it is open. They open
                without animating: a height transition re-lays out the results table below on every frame. Both panels
                stay mounted and are only hidden when closed (Mantine's default hides them in an Activity, which re-runs
                every input's effects on each open). */}
            <SimpleGrid cols={{ base: 1, lg: 2 }} style={{ alignItems: 'start' }}>
              <Accordion
                multiple
                variant="separated"
                transitionDuration={0}
                keepMountedMode="display-none"
                value={open}
                onChange={(v) => toggleSection('advanced', v)}
              >
                <Accordion.Item value="advanced">
                  <Accordion.Control>Advanced Filters</Accordion.Control>
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
                        <Stack mt={4} gap="xs">
                          {EXITS.map((e) => (
                            <Checkbox key={e.value} value={e.value} label={e.label} description={e.description} />
                          ))}
                        </Stack>
                      </Checkbox.Group>
                      <SimpleGrid cols={{ base: 1, sm: 3, lg: 1 }}>
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
              <Accordion
                multiple
                variant="separated"
                transitionDuration={0}
                keepMountedMode="display-none"
                value={open}
                onChange={(v) => toggleSection('time', v)}
              >
                <Accordion.Item value="time">
                  <Accordion.Control>Time assumptions</Accordion.Control>
                  <Accordion.Panel>
                    <TimeSettingsPanel />
                  </Accordion.Panel>
                </Accordion.Item>
              </Accordion>
            </SimpleGrid>
            </>
          )}
          {status.data.prices === 0 && (
            <Alert color="yellow">
              No prices yet for this realm. Scan the auction house with Auctionator, then upload Auctionator.lua on the
              Upload page.
            </Alert>
          )}
          {selection &&
            (debouncedFilters.exits.length ? (
              <Results filters={debouncedFilters} browsing={browsing} />
            ) : (
              <Alert>Pick at least one way to sell under Advanced Filters.</Alert>
            ))}
        </>
      )}
    </Stack>
  )
}
