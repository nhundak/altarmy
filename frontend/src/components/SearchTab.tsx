import { memo, type ReactNode, useEffect, useId, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Card,
  Checkbox,
  Group,
  Loader,
  NumberInput,
  Radio,
  Select,
  SimpleGrid,
  Stack,
  Text,
  Tooltip,
  useMantineTheme,
  VisuallyHidden,
} from '@mantine/core'
import { useMediaQuery } from '@mantine/hooks'
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
  useProfessions,
  useRank,
  useSelectRealm,
  useSetAhBlocked,
  useSetFavorite,
  useStatus,
} from '../api/queries'
import { goldToCopper } from '../lib/money'
import { fromKey, realmOptions, toKey } from '../lib/realms'
import { useSession } from '../lib/session'
import {
  ALL_EXITS,
  answer,
  hasEnchanter,
  nextStep,
  presetsFor,
  professionsOf,
  skillCrafters,
  rankProfessions,
  rankSort,
  setupSchema,
  type Setup as SetupAnswers,
  type Step,
} from '../lib/setup'
import { useStoredState } from '../lib/storage'
import { IconInfo } from './icons'
import { HOW_TO_SCAN } from './PriceFreshness'
import { PriceSignal } from './PriceSignal'
import { RealmCard } from './RealmCard'
import { ResultsTable } from './ResultsTable'
import { Setup } from './Setup'
import { CraftsPerSession, TimeSettingsPanel } from './TimeSettingsPanel'

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
/**
 * One way to sell: its checkbox, with the explanation in a tooltip beside it (and as the checkbox's description for
 * screen readers), so the options stay one short row.
 */
function SellVia({ value, label, description }: (typeof EXITS)[number]) {
  const id = useId()
  return (
    <Group gap={6} wrap="nowrap">
      <Checkbox value={value} label={label} aria-describedby={id} />
      <VisuallyHidden id={id}>{description}</VisuallyHidden>
      <Tooltip label={description} multiline w={280} withArrow events={{ hover: true, focus: false, touch: true }}>
        <Text component="span" c="dimmed" lh={0} aria-hidden="true">
          <IconInfo size={15} />
        </Text>
      </Tooltip>
    </Group>
  )
}

/**
 * The options' card. Where its columns stack (below the `sm` breakpoint) it is a Filters section, closed until opened,
 * so the results are not pushed a screen down; its content stays mounted either way.
 */
function Options({ children }: { children: ReactNode }) {
  const theme = useMantineTheme()
  // the complement of SimpleGrid's own `sm` query, so the section folds exactly where the columns stack
  const small = useMediaQuery(`not all and (min-width: ${theme.breakpoints.sm})`)
  const [open, setOpen] = useState<string | null>(null)
  if (!small) {
    return (
      <Card withBorder padding="lg" component="section" aria-label="Options">
        {children}
      </Card>
    )
  }
  return (
    <Accordion
      variant="separated"
      transitionDuration={0}
      keepMountedMode="display-none"
      value={open}
      onChange={setOpen}
    >
      <Accordion.Item value="filters">
        <Accordion.Control>Filters</Accordion.Control>
        <Accordion.Panel>{children}</Accordion.Panel>
      </Accordion.Item>
    </Accordion>
  )
}

const UNLEARNED: { value: Unlearned; label: string }[] = [
  { value: 'none', label: 'Show recipes I already know' },
  { value: 'soon', label: 'Include recipes I can train soon (20 skill points)' },
  { value: 'all', label: 'Include all recipes' },
]
const SECTIONS = ['advanced', 'time'] as const
const NONE_OPEN: string[] = []
const storedSetup = setupSchema.nullable()
const exitList = z.array(z.enum(['vendor', 'disenchant', 'ah']))
const EVERY_EXIT: Exit[] = [...ALL_EXITS]

const bound = z.number().nullable()
/** NumberInput reports an empty field as ''; that means no bound. */
const toBound = (v: number | string) => (typeof v === 'number' ? v : null)
const scaled = (v: number | null, f: (v: number) => number) => (v === null ? null : f(v))

type Filters = Omit<RankParams, 'top'>

/**
 * `value` once it has stopped changing for `wait` ms (typing a bound re-ranks once, not per key), except that a new
 * `flush` (a setup question just answered) takes it at once, so the results never show a request with the filters of
 * the answer before.
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
          skillCrafters: filters.skillCrafters,
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
 * The search: first the setup's questions (what the user is after, then a profession, or how to sell and what a session
 * ), then the realm card (realm and faction, price freshness, an upload in place) and, with a realm, the options
 * (recipes, skill-ups only, sell via, crafts per session), advanced filters, time assumptions and ranked recipes. The answers decide the ranking's order and preset the filters they are about; they are remembered per user,
 * like the Profit page's start.
 */
export function SearchTab() {
  const { uid } = useSession()
  const status = useStatus()
  const characters = useCharacters()
  const coverage = useCoverage()
  const select = useSelectRealm()
  const professionNames = useProfessions().data
  const [setup, setSetup] = useStoredState<SetupAnswers | null>(`altarmy-profit.setup.${uid}`, storedSetup, null)
  // Skilling up needs the characters' professions: without imported characters it can't be picked (and a saved
  // setup asks again).
  const noCharacters = characters.data !== undefined && characters.data.groups.length === 0
  // A question the user reopened from the summary; otherwise the first unanswered one is shown.
  const [editing, setEditing] = useState<Step | null>(null)
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
  const [exits, setExits] = useStoredState<Exit[]>('altarmy-profit.search.exits', exitList, EVERY_EXIT)
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useStoredState('altarmy-profit.search.minCost', bound, 0)
  const [maxCost, setMaxCost] = useStoredState('altarmy-profit.search.maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useStoredState('altarmy-profit.search.minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useStoredState('altarmy-profit.search.maxProfit', bound, null)
  const [minRoi, setMinRoi] = useStoredState('altarmy-profit.search.minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useStoredState('altarmy-profit.search.maxRoi', bound, null)
  const groups = characters.data?.groups ?? []
  // Show the realm being switched to while the server imports its prices.
  const selection = select.isPending ? select.variables : status.data?.selection
  const group = groups.find((g) => selection && toKey(g) === toKey(selection))
  const professions = professionsOf(group, professionNames)
  // By value, not the stored object: a new but equal setup must not count as new filters (that resets paging).
  const sort = rankSort(setup)
  const [profession = null] = rankProfessions(setup)
  // Joined, for the same reason (character names never hold a comma).
  const skilled = skillCrafters(setup, professions).join(',')
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
      professions: profession === null ? [] : [profession],
      skillCrafters: skilled ? skilled.split(',') : [],
      sort,
    }),
    [unlearned, includeTrivial, exits, minCost, maxCost, minProfit, maxProfit, minRoi, maxRoi, sort, profession, skilled],
  )
  const [picks, setPicks] = useState(0)
  const debouncedFilters = useSettled(filters, 300, picks)

  /** Answer one question, writing the filters that answer presets (the user may change them afterwards). */
  const pick = (step: Step, value: string, characters?: string[]) => {
    const next = answer(setup, step, value, characters)
    setSetup(next)
    setEditing(null)
    setPicks((n) => n + 1)
    const presets = presetsFor(next, step)
    if (presets.includeTrivial !== undefined) setIncludeTrivial(presets.includeTrivial)
    if (presets.minProfit !== undefined) setMinProfit(presets.minProfit)
    if (presets.minRoi !== undefined) setMinRoi(presets.minRoi)
    if (presets.unlearned !== undefined) setUnlearned(presets.unlearned)
    if (presets.exits !== undefined) setExits(presets.exits)
  }

  if (status.isPending || characters.isPending) return <Loader />
  if (status.isError) return <Alert color="red">{status.error.message}</Alert>
  if (status.data.recipes === 0) {
    return (
      <Alert color="red">
        No game data has been loaded yet. If you run this site, run `altarmy-profit ingest`.
      </Alert>
    )
  }

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
  const step = editing ?? nextStep(setup, professions, noCharacters)
  const realmSelect = (size?: 'md') => (
    <Select
      label="Realm and faction"
      placeholder="No realm has prices yet"
      data={grouped}
      value={selection ? toKey(selection) : null}
      onChange={(key) => key && select.mutate(fromKey(key))}
      allowDeselect={false}
      size={size}
      maw={size ? 480 : 420}
    />
  )

  return (
    <Stack>
      <PriceSignal />
      <Setup
        setup={setup}
        step={step}
        professions={professions}
        onPick={pick}
        onOpen={setEditing}
        unavailable={noCharacters ? { skill: 'Import your characters first, so we know which skills they have.' } : {}}
      >
        {/* Which professions there are depends on the realm: it can be changed right there. */}
        {step === 'profession' && realmSelect()}
      </Setup>
      {step === null && (
        <>
          <RealmCard select={realmSelect('md')} lastScan={selection ? lastScan : undefined} />
          {selection && (
            <Options>
              <SimpleGrid cols={{ base: 1, sm: browsing ? 2 : 3 }} spacing="xl">
                {!browsing && (
                  <Stack gap="md">
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
                    {/* Stored as includeTrivial, the API's parameter: checked means trivial recipes are left out. */}
                    <Checkbox
                      label="Show only recipes that can give a skill up"
                      checked={!includeTrivial}
                      onChange={(e) => setIncludeTrivial(!e.currentTarget.checked)}
                    />
                  </Stack>
                )}
                <Checkbox.Group
                  label="Sell via"
                  value={exits}
                  onChange={(v) => setExits(ALL_EXITS.filter((e) => v.includes(e)))}
                >
                  <Stack mt={4} gap="xs">
                    {EXITS.map((e) => (
                      <SellVia key={e.value} {...e} />
                    ))}
                  </Stack>
                </Checkbox.Group>
                <CraftsPerSession />
              </SimpleGrid>
            </Options>
          )}
          {selection && !browsing && !hasEnchanter(group) && (
            <Alert color="yellow" title="Nobody here can disenchant">
              None of your characters on {selection.realm} has Enchanting, so nothing can be disenchanted. Levelling
              Enchanting on any alt is an easy way to expand your options: enchanting materials sell reliably.
              {setup?.aim === 'gold' && setup.selling === 'reliable' && ' Until then only vendor sales count.'}
            </Alert>
          )}
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
              No prices yet for this realm. {HOW_TO_SCAN}
            </Alert>
          )}
          {selection &&
            (debouncedFilters.exits.length ? (
              <Results filters={debouncedFilters} browsing={browsing} />
            ) : (
              <Alert>Pick at least one way to sell under Sell via.</Alert>
            ))}
        </>
      )}
    </Stack>
  )
}
