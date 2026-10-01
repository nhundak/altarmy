import { Fragment, memo, type ReactNode, useEffect, useId, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Group,
  Loader,
  NumberInput,
  Radio,
  Select,
  SimpleGrid,
  Slider,
  Stack,
  Text,
  Tooltip,
  useMantineTheme,
  VisuallyHidden,
} from '@mantine/core'
import { z } from 'zod'
import {
  ALL_SOURCES,
  type Exit,
  MAX_LOOK_AHEAD,
  type RankParams,
  type Source,
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
import classes from './SearchTab.module.css'
import { ResultsTable } from './ResultsTable'
import { Setup } from './Setup'
import { CraftsPerSession, TimeSettingsPanel } from './TimeSettingsPanel'

/** Results per page: the first request asks for this many, and each "Show more" for this many more. */
const PAGE = 50

const EXITS: { value: Exit; label: string; description: string; warning?: string; aside?: string }[] = [
  {
    value: 'vendor',
    label: 'Vendor',
    description: "Dead simple, 100% reliable. It's rarely profitable, but use it if you can.",
  },
  {
    value: 'disenchant',
    label: 'Disenchant',
    description:
      'Enchanting materials tend to have stable prices and sell well. Usually the most reliable way to turn a profit.',
    aside:
      'Enabling this will also look for cases where converting essences is profitable (3 lesser to 1 greater, ' +
      'or back), and cases where gear can be bought, disenchanted, and resold.',
  },
  {
    value: 'ah',
    label: 'Auction house',
    description: 'Volatile, unpredictable, but potentially lucrative.',
    warning: 'You will need to take an active role in figuring out what sells reliably.',
  },
]
const DEAD_LOSS = 'This is a dead loss unless you can find someone to pay you for it, but you do what you got to do.'
/** The professions with spells that enhance an item and make none (enchants, Engineering's tinkers), each with how
 * the tooltip puts it. Only while one of them is skilled up is the option offered: such casts sell nothing, so they
 * rank at a dead loss. */
const SKILL_ONLY_WHY: Readonly<Record<string, string>> = {
  enchanting: `Sometimes to level up enchanting, you just need to repeatedly enchant stuff. ${DEAD_LOSS}`,
  engineering: `Sometimes to level up engineering, you just need to repeatedly tinker with your gear. ${DEAD_LOSS}`,
}
const SKILL_ONLY = { value: 'skill', label: 'Enhance item for skill up only' } as const
/** The Disenchant tooltip's extra line when none of the selected realm's characters has Enchanting. */
/** The Arcane Salvager checkbox is hidden for now: while it is, disenchants never count on a salvager. */
export const SHOW_ARCANE_SALVAGER = false

const NO_ENCHANTER = 'None of your characters here has Enchanting, so nothing can be disenchanted.'

/**
 * One way to sell: its checkbox, with the explanation in a tooltip beside it (and as the checkbox's description for
 * screen readers), so the options stay one short row. A `warning` sentence follows the explanation in a warning
 * colour, an `aside` (a secondary detail) goes on a line of its own in smaller, fainter text, and a `note` (something
 * about the user's characters) on a line of its own in the warning colour.
 */
function SellVia({
  value,
  label,
  description,
  warning,
  aside,
  note,
}: (typeof EXITS)[number] & { note?: string | undefined }) {
  const id = useId()
  const text = [description, warning, aside, note].filter(Boolean).join(' ')
  const tooltip = (
    <>
      {description}
      {warning && (
        <>
          {' '}
          <span className={classes.warning}>{warning}</span>
        </>
      )}
      {aside && <div className={classes.aside}>{aside}</div>}
      {note && <div className={classes.warning}>{note}</div>}
    </>
  )
  return (
    <Group gap={6} wrap="nowrap">
      <Checkbox value={value} label={label} aria-describedby={id} />
      <VisuallyHidden id={id}>{text}</VisuallyHidden>
      <Tooltip label={tooltip} multiline w={280} withArrow events={{ hover: true, focus: false, touch: true }}>
        <Text component="span" c="dimmed" lh={0} aria-hidden="true">
          <IconInfo size={15} />
        </Text>
      </Tooltip>
    </Group>
  )
}

/**
 * The options, a Filters section. It starts open, except where its columns stack (below the `sm` breakpoint): there
 * it starts closed, so the results are not pushed a screen down. Its content stays mounted either way.
 */
function Options({ children }: { children: ReactNode }) {
  const theme = useMantineTheme()
  // the complement of SimpleGrid's own `sm` query, so the section starts closed exactly where the columns stack
  const [open, setOpen] = useState<string | null>(() =>
    window.matchMedia(`not all and (min-width: ${theme.breakpoints.sm})`).matches ? null : 'filters',
  )
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
  { value: 'none', label: 'Show all recipes I already know' },
  { value: 'train', label: 'Include recipes I can train' },
  { value: 'all', label: 'Include all recipes' },
]
/** The stored choice; "now" and "soon", from before the look-ahead was a slider, read as recipes to train. */
const storedUnlearned = z.preprocess(
  (v) => (v === 'now' || v === 'soon' ? 'train' : v),
  z.enum(['none', 'train', 'all']),
)
const LOOK_AHEAD_STEP = 5
const storedLookAhead = z.number().int().min(0).max(MAX_LOOK_AHEAD).multipleOf(LOOK_AHEAD_STEP)
const SOURCES: { value: Source; label: string }[] = [
  { value: 'trainer', label: 'Taught by trainers' },
  { value: 'recipe', label: 'Taught by normal recipes' },
  { value: 'bop', label: 'Taught by bind on pickup looted recipes' },
]
const sourceList = z.array(z.enum(['trainer', 'recipe', 'bop']))
const DEFAULT_SOURCES: Source[] = ['trainer', 'recipe']
const LOOK_AHEAD_MARKS = [0, 10, 20, 30, 40, 50].map((value) => ({ value, label: String(value) }))

/** The options of "Include recipes I can train", set in under it: how far to look ahead, and what may teach them. */
function TrainOptions({
  lookAhead,
  onLookAhead,
  sources,
  onSources,
}: {
  lookAhead: number
  onLookAhead: (points: number) => void
  sources: Source[]
  onSources: (sources: Source[]) => void
}) {
  return (
    <Stack gap="sm" className={classes.suboptions} role="group" aria-label="Recipes I can train">
      <div>
        <Text size="sm">
          Skill points to look ahead: <b>{lookAhead}</b>
        </Text>
        <Text size="xs" c="dimmed">
          {lookAhead === 0
            ? 'Only recipes that can be trained right now.'
            : `Also recipes needing up to ${lookAhead} more skill ${lookAhead === 1 ? 'point' : 'points'}.`}
        </Text>
        <Slider
          mt={6}
          mb="lg"
          size="sm"
          min={0}
          max={MAX_LOOK_AHEAD}
          step={LOOK_AHEAD_STEP}
          marks={LOOK_AHEAD_MARKS}
          value={lookAhead}
          onChange={onLookAhead}
          thumbLabel="Skill points to look ahead"
        />
      </div>
      <Checkbox.Group
        aria-label="Recipe sources"
        value={sources}
        onChange={(v) => onSources(ALL_SOURCES.filter((s) => v.includes(s)))}
      >
        <Stack gap={6}>
          {SOURCES.map((s) => (
            <Checkbox key={s.value} size="xs" value={s.value} label={s.label} />
          ))}
        </Stack>
      </Checkbox.Group>
    </Stack>
  )
}
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
          lookAhead: filters.lookAhead,
          sources: filters.sources,
          includeTrivial: filters.includeTrivial,
          skillCrafters: filters.skillCrafters,
          exits: filters.exits,
          arcaneSalvager: filters.arcaneSalvager,
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
 * (recipes, skill-ups only, sell via, crafts per session, Arcane Salvager), advanced filters, time assumptions and ranked recipes. The answers decide the ranking's order and preset the filters they are about; they are remembered per user,
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
    storedUnlearned,
    'none',
  )
  // Both only count for recipes to train, and are kept while another option is picked.
  const [lookAhead, setLookAhead] = useStoredState('altarmy-profit.search.lookAhead', storedLookAhead, 0)
  const [sources, setSources] = useStoredState<Source[]>('altarmy-profit.search.sources', sourceList, DEFAULT_SOURCES)
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
  // Kept apart from the ways to sell: it only counts (and shows) while Enchanting is being skilled up.
  const [skillOnly, setSkillOnly] = useStoredState('altarmy-profit.search.skillOnly', z.boolean(), false)
  // null until the user ticks or unticks it: then it follows whether any character can make an Arcane Salvager.
  const [salvagerPick, setSalvagerPick] = useStoredState<boolean | null>(
    'altarmy-profit.search.arcaneSalvager',
    z.boolean().nullable(),
    null,
  )
  const arcaneSalvager = SHOW_ARCANE_SALVAGER && (salvagerPick ?? characters.data?.arcane_salvager ?? false)
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
  const skillOnlyWhy = SKILL_ONLY_WHY[profession?.toLowerCase() ?? '']
  const enhancing = skillOnlyWhy !== undefined
  // Whether casts made for the skill point alone are ranked: only while such a profession is the one skilled up.
  const skilling = enhancing && skillOnly
  // Joined, for the same reason (character names never hold a comma).
  const skilled = skillCrafters(setup, professions).join(',')
  const filters = useMemo<Filters>(
    () => ({
      unlearned,
      lookAhead,
      sources: ALL_SOURCES.filter((s) => sources.includes(s)),
      includeTrivial,
      exits: [...ALL_EXITS.filter((e) => exits.includes(e)), ...(skilling ? [SKILL_ONLY.value] : [])],
      arcaneSalvager,
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
    [unlearned, lookAhead, sources, includeTrivial, exits, skilling, arcaneSalvager, minCost, maxCost, minProfit, maxProfit, minRoi, maxRoi, sort, profession, skilled],
  )
  const [picks, setPicks] = useState(0)
  // Flushed once the characters load too: the Arcane Salvager's default comes from them.
  const debouncedFilters = useSettled(filters, 300, characters.data ? picks : -1)

  /** Answer one question, writing the filters that answer presets (the user may change them afterwards). */
  const pick = (step: Step, value: string, characters?: string[]) => {
    const next = answer(setup, step, value, characters)
    setSetup(next)
    // an aim always asks its follow-up (which profession, how to sell), even when an answer is kept from before
    setEditing(step === 'aim' ? (next.aim === 'skill' ? 'profession' : 'selling') : null)
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
  const noEnchanter = !!selection && !browsing && !hasEnchanter(group)
  const options = realmOptions(groups, coverage.data ?? [])
  // The characters' realms come first, without a heading; the other priced realms under Browse a realm.
  const item = ({ value, label }: { value: string; label: string }) => ({ value, label })
  const browse = options.filter((o) => o.section === 'Browse a realm').map(item)
  if (selection && !options.some((o) => o.value === toKey(selection))) {
    // e.g. a realm whose scan is still being merged: still show what is selected
    browse.push({ value: toKey(selection), label: selection.realm })
  }
  const realmData = [
    ...options.filter((o) => o.section === 'Your characters').map(item),
    ...(browse.length > 0 ? [{ group: 'Browse a realm', items: browse }] : []),
  ]
  // The selection's auction house and its newest scan; undefined while the coverage is still loading.
  const house = coverage.data?.find((c) => c.auction_house_id === status.data.auction_house_id)
  const lastScan = coverage.data && status.data.auction_house_id !== null ? (house?.last_scan ?? null) : undefined
  const step = editing ?? nextStep(setup, professions, noCharacters)
  // In the realm card the picker has no visible label (it sits beside the upload buttons), only its accessible name.
  const realmSelect = (inCard = false) => (
    <Select
      label={inCard ? undefined : 'Realm'}
      aria-label={inCard ? 'Realm' : undefined}
      placeholder="No realm has prices yet"
      data={realmData}
      value={selection ? toKey(selection) : null}
      onChange={(key) => key && select.mutate(fromKey(key))}
      allowDeselect={false}
      size={inCard ? 'sm' : undefined}
      w={inCard ? 300 : undefined}
      maw={inCard ? '100%' : 420}
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
        unavailable={noCharacters ? { skill: 'Upload your characters first, so we know which skills they have.' } : {}}
      >
        {/* Which professions there are depends on the realm: it can be changed right there. */}
        {step === 'profession' && realmSelect()}
      </Setup>
      {step === null && (
        <>
          <RealmCard select={realmSelect(true)} lastScan={selection ? lastScan : undefined} />
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
                          <Fragment key={o.value}>
                            <Radio value={o.value} label={o.label} />
                            {o.value === 'train' && unlearned === 'train' && (
                              <TrainOptions
                                lookAhead={lookAhead}
                                onLookAhead={setLookAhead}
                                sources={sources}
                                onSources={setSources}
                              />
                            )}
                          </Fragment>
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
                  value={skilling ? [...exits, SKILL_ONLY.value] : exits}
                  onChange={(v) => {
                    setExits(ALL_EXITS.filter((e) => v.includes(e)))
                    if (enhancing) setSkillOnly(v.includes(SKILL_ONLY.value))
                  }}
                >
                  <Stack mt={4} gap="xs">
                    {EXITS.map((e) => (
                      <SellVia
                        key={e.value}
                        {...e}
                        note={e.value === 'disenchant' && noEnchanter ? NO_ENCHANTER : undefined}
                      />
                    ))}
                    {skillOnlyWhy !== undefined && <SellVia {...SKILL_ONLY} description={skillOnlyWhy} />}
                  </Stack>
                </Checkbox.Group>
                <Stack gap="md">
                  <CraftsPerSession />
                  {SHOW_ARCANE_SALVAGER && (
                    <Checkbox
                      label="Use Arcane Salvager for disenchanting"
                      description="10% chance of extra disenchanting materials. Usable only at campfires."
                      checked={arcaneSalvager}
                      onChange={(e) => setSalvagerPick(e.currentTarget.checked)}
                    />
                  )}
                </Stack>
              </SimpleGrid>
            </Options>
          )}
          {noEnchanter && (
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
