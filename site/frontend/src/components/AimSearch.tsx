import { memo, type ReactNode, useEffect, useId, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Group,
  Loader,
  NumberInput,
  Select,
  SimpleGrid,
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
  type RankParams,
  type RankSort,
  type VerdictLevel,
  type Source,
  useAhBlocked,
  useDataVersion,
  useFavorites,
  useRank,
  useSetAhBlocked,
  useSetFavorite,
} from '../api/queries'
import { goldToCopper } from '../lib/money'
import {
  ALL_EXITS,
  type Aim,
  legacySearchKey,
  type ProfessionChoice,
  rankProfessions,
  rankSort,
  searchKey,
  type Setup as SetupAnswers,
  SKILL_EXITS,
  skillCrafters,
} from '../lib/setup'
import { DEFAULT_REACH_TARGET, MAX_REACH_TARGET, MIN_REACH_TARGET } from '../lib/skill'
import { useStoredState } from '../lib/storage'
import { IconInfo } from './icons'
import { HOW_TO_SCAN } from './PriceFreshness'
import classes from './SearchTab.module.css'
import { ResultsTable } from './ResultsTable'
import { SkillWorkspace } from './SkillWorkspace'
import { CraftsPerSession } from './CraftsPerSession'

/** Results per page: the first request asks for this many, and each "Show more" for this many more. */
const PAGE = 50

const EXITS: {
  value: Exit
  label: string
  description: string
  warning?: string
  aside?: string
}[] = [
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
const SKILL_ONLY = {
  value: 'skill',
  label: 'Enhance item for skill up only',
} as const
/** The Arcane Salvager checkbox is hidden for now: while it is, disenchants never count on a salvager. */
export const SHOW_ARCANE_SALVAGER = false

/** The Disenchant tooltip's extra line when none of the selected realm's characters has Enchanting. */
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
}: {
  value: string
  label: string
  description: string
  warning?: string | undefined
  aside?: string | undefined
  note?: string | undefined
}) {
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
 * The options, a section named `label`. It starts open, except where its columns stack (below the `sm` breakpoint): there
 * it starts closed, so the results are not pushed a screen down. Its content stays mounted either way.
 */
function Options({ label, children }: { label: string; children: ReactNode }) {
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
        <Accordion.Control>{label}</Accordion.Control>
        <Accordion.Panel>{children}</Accordion.Panel>
      </Accordion.Item>
    </Accordion>
  )
}

const SOURCES: { value: Source; label: string; description?: string }[] = [
  { value: 'trainer', label: 'Taught by trainers' },
  {
    value: 'recipe',
    label: 'Taught by normal recipes',
    description:
      'Includes recipes sold by vendors (even if they are bind-on-pickup) and non-soulbound recipes you could find on the auction house.',
  },
  { value: 'bop', label: 'Taught by bind on pickup recipes' },
]
const sourceList = z.array(z.enum(['trainer', 'recipe', 'bop']))
const DEFAULT_SOURCES: Source[] = ['trainer', 'recipe']
const SECTIONS = ['advanced'] as const
const NONE_OPEN: string[] = []
const exitList = z.array(z.enum(['vendor', 'disenchant', 'ah', 'keep']))
const EVERY_EXIT: Exit[] = [...ALL_EXITS]

const bound = z.number().nullable()
/** NumberInput reports an empty field as ''; that means no bound. */
const toBound = (v: number | string) => (typeof v === 'number' ? v : null)
const scaled = (v: number | null, f: (v: number) => number) => (v === null ? null : f(v))

type Filters = Omit<RankParams, 'top'>

const ANY_VERDICT = 'any'
const VERDICT_OPTIONS = [
  { value: ANY_VERDICT, label: 'Any' },
  { value: 'likely', label: 'Likely or steady' },
  { value: 'steady', label: 'Steady' },
]
const verdictSchema = z.enum(['steady', 'likely', 'unproven']).nullable()
/** The gold list's orders, all the server's (over the whole ranking, not just the rows loaded). */
const GOLD_SORTS: { value: RankSort; label: string }[] = [
  { value: 'likely', label: 'Likely profit' },
  { value: 'all_sell', label: 'Profit if all sell' },
  { value: 'roi', label: 'ROI' },
  { value: 'spend', label: 'Least spent' },
  { value: 'profit_each', label: 'Profit each' },
]
const goldSortSchema = z.enum(['likely', 'all_sell', 'roi', 'spend', 'profit_each'])
/** Under this many hours of back-to-back scans this week, a house's sales are barely seen. */
const WATCHED_ENOUGH_HOURS = 3

/**
 * `value` once it has stopped changing for `wait` ms (typing a bound re-ranks once, not per key), except that a new
 * `flush` (the characters just loaded) takes it at once, so the results never show a request with stale filters.
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
const Results = memo(function Results({ filters, browsing }: { filters: Filters; browsing: boolean }) {
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
  const { results, total, items } = rank.data
  const skill = filters.sort === 'skill'
  if (!results.length) {
    return (
      <Stack>
        <Alert>
          {browsing
            ? 'No recipes match these filters with the current prices.'
            : 'No recipes match these filters for these characters with the current prices.'}
        </Alert>
      </Stack>
    )
  }
  return (
    <Stack>
      <ResultsTable
        results={results}
        items={items}
        classes={rank.data.classes}
        learn={rank.data.learn}
        params={{
          unlearned: filters.unlearned,
          lookAhead: filters.lookAhead,
          sources: filters.sources,
          includeTrivial: filters.includeTrivial,
          skillCrafters: filters.skillCrafters,
          exits: filters.exits,
          arcaneSalvager: filters.arcaneSalvager,
          runs: filters.runs,
          version,
        }}
        ahBlocked={ahBlocked}
        onSetAhBlocked={(itemId, blocked) => setAhBlocked({ itemId, blocked })}
        favorites={favorites}
        onSetFavorite={(recipeId, favorite) => setFavorite({ recipeId, favorite })}
        rankBy={filters.sort === 'skill' ? 'skill' : 'gold'}
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
      {skill && (
        <Text size="xs" c="dimmed">
          Skill points from crafting a recipe&apos;s reagents yourself (bolts of cloth, say) aren&apos;t counted yet.
        </Text>
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

/** A chance to reach a run's target, in whole percent within what is offered. */
const reachTarget = (v: number) => Math.min(MAX_REACH_TARGET, Math.max(MIN_REACH_TARGET, Math.round(v)))

/** "a" or "an" before a percent as said aloud ("an 80%", "a 95%"), for the percents on offer. */
const article = (percent: number) => (String(percent).startsWith('8') ? 'an' : 'a')

/** How sure the materials bought for a run are to get it to its target skill, what that means in a tooltip beside it. */
function ReachTarget({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const shown = reachTarget(value)
  return (
    <NumberInput
      label={
        <Group gap={6} wrap="nowrap" component="span">
          Chance to reach target skill
          <Tooltip
            label={
              <>
                Since skill ups are random, we can&apos;t predict exactly how many times you&apos;ll need to craft each
                recipe. With this setting, we&apos;ll choose the number of crafts so you have {article(shown)} {shown}% chance to reach
                the target skill level
                <br />
                <br />
                Put another way: {shown}% of the time, you won&apos;t need to make a second trip to the auction house
              </>
            }
            multiline
            w={280}
            withArrow
            events={{ hover: true, focus: false, touch: true }}
          >
            <Text component="span" c="dimmed" lh={0} aria-hidden="true">
              <IconInfo size={15} />
            </Text>
          </Tooltip>
        </Group>
      }
      value={value}
      onChange={(v) => {
        if (typeof v === 'number') onChange(v)
      }}
      onBlur={() => onChange(shown)}
      min={MIN_REACH_TARGET}
      max={MAX_REACH_TARGET}
      clampBehavior="blur"
      allowDecimal={false}
      allowNegative={false}
      suffix="%"
      step={5}
      styles={{ wrapper: { maxWidth: 120 } }}
    />
  )
}

/** A filter of the aim's search: kept under the aim's own key, starting from where every filter used to be kept. */
function useFilter<T>(aim: Aim, name: string, schema: z.ZodType<T>, defaultValue: T) {
  return useStoredState(searchKey(aim, name), schema, defaultValue, legacySearchKey(name))
}


/**
 * One aim's search, once the setup is complete and a realm is selected: its options and ranked recipes. Mounted per
 * aim (`key={aim}`), so each remembers its own filters: making gold and skilling up never overwrite each other's.
 *
 * Making gold ranks every recipe the characters know by the profit of a session, with Filters (how to sell, crafts
 * per session) and Advanced Filters (bounds, price confidence).
 *
 * Skilling up ranks every recipe the one skilled up can make or train now that still gives them a skill point, each
 * as a useful run (the crafts until it turns green, or yellow: `stop`), by what a skill point costs; what is made is
 * sold to a vendor or disenchanted, else kept. Its Skill options: what may teach the recipes, where a run stops
 * and, for Enchanting and Engineering, casts made for the skill point alone.
 */
export function AimSearch({
  setup,
  professions,
  browsing,
  noEnchanter,
  realm,
  noPrices,
  salvagerDefault,
  flush,
  onUpload,
  lastScan,
  watchedHours,
  houseId,
}: {
  setup: SetupAnswers
  /** the selected realm's professions, with who has them */
  professions: readonly ProfessionChoice[]
  /** no characters on the selected realm: every recipe, for one unnamed crafter */
  browsing: boolean
  noEnchanter: boolean
  realm: string
  noPrices: boolean
  /** whether a character can make an Arcane Salvager: the checkbox's default */
  salvagerDefault: boolean
  /** changes once the characters load, so the first request already has their defaults */
  flush: number
  /** open the realm card's Upload your scan */
  onUpload: () => void
  /** the auction house's newest scan; null: never scanned; undefined: unknown yet */
  lastScan?: string | null | undefined
  /** hours of back-to-back scans of it this week (sales are seen only then); undefined: unknown */
  watchedHours?: number | undefined
  houseId?: number | null
}) {
  const { aim } = setup
  const skill = aim === 'skill'
  const [sources, setSources] = useFilter<Source[]>(aim, 'sources', sourceList, DEFAULT_SOURCES)
  // Stored as strings: sections that no longer exist (the old Characters and Time assumptions ones) are dropped,
  // not an error.
  const [stored, setOpen] = useFilter(aim, 'open', z.array(z.string()), NONE_OPEN)
  const open = SECTIONS.filter((s) => stored.includes(s))
  const [exits, setExits] = useFilter<Exit[]>(aim, 'exits', exitList, EVERY_EXIT)
  // Kept apart from the ways to sell: it only counts (and shows) while Enchanting is being skilled up.
  const [skillOnly, setSkillOnly] = useFilter(aim, 'skillOnly', z.boolean(), false)
  // null until the user ticks or unticks it: then it follows whether any character can make an Arcane Salvager.
  const [salvagerPick, setSalvagerPick] = useFilter<boolean | null>(aim, 'arcaneSalvager', z.boolean().nullable(), null)
  const arcaneSalvager = SHOW_ARCANE_SALVAGER && (salvagerPick ?? salvagerDefault)
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useFilter(aim, 'minCost', bound, 0)
  const [maxCost, setMaxCost] = useFilter(aim, 'maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useFilter(aim, 'minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useFilter(aim, 'maxProfit', bound, null)
  const [minRoi, setMinRoi] = useFilter(aim, 'minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useFilter(aim, 'maxRoi', bound, null)
  const [minVerdict, setMinVerdict] = useFilter<VerdictLevel | null>(aim, 'minVerdict', verdictSchema, null)
  const [goldSort, setGoldSort] = useFilter<RankSort>(aim, 'sort', goldSortSchema, 'likely')
  const [learnable, setLearnable] = useFilter(aim, 'learnable', z.boolean(), false)
  // Skill up only: how sure the materials bought for a run are to get there, in percent.
  const [reach, setReach] = useFilter(aim, 'reachTarget', z.number(), DEFAULT_REACH_TARGET)
  // The newest scan's notice, dismissed per auction house.
  const [dismissed, setDismissed] = useStoredState(
    `altarmy-profit.notice.unwatched.${houseId ?? 0}`,
    z.boolean(),
    false,
  )
  // By value, not the stored object: a new but equal setup must not count as new filters (that resets paging).
  const sort = skill ? rankSort(setup) : goldSort
  const [profession = null] = rankProfessions(setup)
  const skillOnlyWhy = skill ? SKILL_ONLY_WHY[profession?.toLowerCase() ?? ''] : undefined
  const enhancing = skillOnlyWhy !== undefined
  // Whether casts made for the skill point alone are ranked: only while such a profession is the one skilled up.
  const skilling = enhancing && skillOnly
  // Joined, for the same reason (character names never hold a comma).
  const skilled = skillCrafters(setup, professions).join(',')
  const filters = useMemo<Filters>(
    () =>
      skill
        ? {
            // Recipes they know or can train now that still give a point, sold to a vendor or kept; no bounds.
            unlearned: 'train',
            lookAhead: 0,
            sources: ALL_SOURCES.filter((s) => sources.includes(s)),
            includeTrivial: false,
            exits: [
              // disenchanting only counts where someone can: the server drops it otherwise
              ...SKILL_EXITS,
              ...(skilling ? (['skill'] as const) : []),
            ],
            arcaneSalvager,
            minCost: null,
            maxCost: null,
            minProfit: null,
            maxProfit: null,
            minRoi: null,
            maxRoi: null,
            minConfidence: null,
            professions: profession === null ? [] : [profession],
            skillCrafters: skilled ? skilled.split(',') : [],
            sort,
            runs: true,
          }
        : {
            // The recipes the characters know (and, if asked, can train now), trivial or not.
            unlearned: learnable ? 'train' : 'none',
            lookAhead: 0,
            sources: DEFAULT_SOURCES,
            includeTrivial: true,
            exits: ALL_EXITS.filter((e) => exits.includes(e)),
            arcaneSalvager,
            minCost: scaled(minCost, goldToCopper),
            maxCost: scaled(maxCost, goldToCopper),
            minProfit: scaled(minProfit, goldToCopper),
            maxProfit: scaled(maxProfit, goldToCopper),
            minRoi: scaled(minRoi, (p) => p / 100),
            maxRoi: scaled(maxRoi, (p) => p / 100),
            minConfidence: null,
            minVerdict,
            professions: [],
            skillCrafters: [],
            sort,
            runs: false,
          },
    [
      skill,
      sources,
      exits,
      skilling,
      arcaneSalvager,
      minCost,
      maxCost,
      minProfit,
      maxProfit,
      minRoi,
      maxRoi,
      minVerdict,
      learnable,
      sort,
      profession,
      skilled,
      stop,
    ],
  )
  const debouncedFilters = useSettled(filters, 300, flush)
  // One character climbing one profession: the skill workspace (the table only until the characters load).
  const climber =
    skill && profession !== null && skilled && !skilled.includes(',')
      ? professions
          .find((p) => p.name.toLowerCase() === profession.toLowerCase())
          ?.holders.find((h) => h.name === skilled)
      : undefined

  const salvager = SHOW_ARCANE_SALVAGER && (
    <Checkbox
      label="Use Arcane Salvager for disenchanting"
      description="10% chance of extra disenchanting materials. Usable only at campfires."
      checked={arcaneSalvager}
      onChange={(e) => setSalvagerPick(e.currentTarget.checked)}
    />
  )

  return (
    <>
      {skill ? (
        <Options label="Skill options">
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="xl">
            <Checkbox.Group
              label="Recipes taught by"
              value={sources}
              onChange={(v) => setSources(ALL_SOURCES.filter((s) => v.includes(s)))}
            >
              <Stack mt={4} gap="xs">
                {SOURCES.map((s) =>
                  s.description ? (
                    <SellVia key={s.value} value={s.value} label={s.label} description={s.description} />
                  ) : (
                    <Checkbox key={s.value} value={s.value} label={s.label} />
                  ),
                )}
              </Stack>
            </Checkbox.Group>
            <Stack gap="md">
              <ReachTarget value={reach} onChange={setReach} />
              {skillOnlyWhy !== undefined && (
                <Checkbox.Group
                  aria-label="Casts for the skill point alone"
                  value={skilling ? [SKILL_ONLY.value] : []}
                  onChange={(v) => setSkillOnly(v.includes(SKILL_ONLY.value))}
                >
                  <SellVia {...SKILL_ONLY} description={skillOnlyWhy} />
                </Checkbox.Group>
              )}
              {salvager}
            </Stack>
          </SimpleGrid>
        </Options>
      ) : (
        <Options label="Filters">
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="xl">
            <Checkbox.Group
              label="Sell via"
              value={exits}
              onChange={(v) => setExits(ALL_EXITS.filter((e) => v.includes(e)))}
            >
              <Stack mt={4} gap="xs">
                {EXITS.map((e) => (
                  <SellVia
                    key={e.value}
                    {...e}
                    note={e.value === 'disenchant' && noEnchanter ? NO_ENCHANTER : undefined}
                  />
                ))}
              </Stack>
            </Checkbox.Group>
            <Stack gap="md">
              <CraftsPerSession />
              <Checkbox
                label="Include recipes I could learn"
                description="Recipes a character can train or buy the pattern for now"
                checked={learnable}
                onChange={(e) => setLearnable(e.currentTarget.checked)}
              />
              {salvager}
            </Stack>
          </SimpleGrid>
        </Options>
      )}
      {!skill && lastScan === null && (
        <Alert color="yellow" title="Nobody has scanned this realm's auction house yet">
          <Group justify="space-between" gap="sm">
            <Text size="sm">Until someone does, only vendor and disenchant values are known. {HOW_TO_SCAN}</Text>
            <Button size="xs" variant="light" onClick={onUpload}>
              Upload your scan
            </Button>
          </Group>
        </Alert>
      )}
      {!skill && lastScan && watchedHours !== undefined && watchedHours < WATCHED_ENOUGH_HOURS && !dismissed && (
        <Alert
          color="blue"
          withCloseButton
          closeButtonLabel="Dismiss"
          onClose={() => setDismissed(true)}
          title={`Sales aren't watched here yet (${watchedHours} h this week)`}
        >
          Two scans 15–30 minutes apart, any time, let everyone here see what sells.
        </Alert>
      )}
      {noEnchanter && (
        <Alert color="yellow" title="Nobody here can disenchant">
          None of your characters on {realm} has Enchanting, so nothing can be disenchanted. Making an enchanter on any
          alt is an easy way to expand your options: enchanting materials sell reliably
          {skill ? ', and disenchanting what you make often costs less than selling it to a vendor.' : '.'}
          {setup.aim === 'gold' && setup.selling === 'reliable' && ' Until then only vendor sales count.'}
        </Alert>
      )}
      {browsing && (
        <Text size="sm" c="dimmed">
          Browsing every recipe on this realm, crafted and sold by one character. Add your characters to see who can
          craft what and what mailing between them costs.
        </Text>
      )}
      {!skill && (
        // A section remembering whether it is open, half the width on large screens. It opens without animating: a
        // height transition re-lays out the results table below on every frame. The panel stays mounted and is
        // only hidden when closed (Mantine's default hides it in an Activity, which re-runs every input's effects
        // on each open).
        <SimpleGrid cols={{ base: 1, lg: 2 }} style={{ alignItems: 'start' }}>
          <Accordion
            multiple
            variant="separated"
            transitionDuration={0}
            keepMountedMode="display-none"
            value={open}
            onChange={(v) => setOpen(SECTIONS.filter((s) => v.includes(s)))}
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
                    <Select
                      label="Minimum sale verdict"
                      description="How sure a sale must be to sell: steady, likely, or anything"
                      data={VERDICT_OPTIONS}
                      value={minVerdict ?? ANY_VERDICT}
                      onChange={(v) => setMinVerdict(v === 'steady' || v === 'likely' ? v : null)}
                      allowDeselect={false}
                    />
                  </SimpleGrid>
                </Stack>
              </Accordion.Panel>
            </Accordion.Item>
          </Accordion>
        </SimpleGrid>
      )}
      {noPrices && <Alert color="yellow">No prices yet for this realm. {HOW_TO_SCAN}</Alert>}
      {!skill && (
        <Select
          label="Sort by"
          data={GOLD_SORTS}
          value={goldSort}
          onChange={(v) => setGoldSort(GOLD_SORTS.find((o) => o.value === v)?.value ?? 'likely')}
          allowDeselect={false}
          w={220}
        />
      )}
      {!debouncedFilters.exits.length ? (
        <Alert>Pick at least one way to sell under Sell via.</Alert>
      ) : climber && profession !== null ? (
        <SkillWorkspace
          filters={debouncedFilters}
          climber={climber}
          profession={profession}
          reachTarget={reachTarget(reach)}
        />
      ) : (
        <Results filters={debouncedFilters} browsing={browsing} />
      )}
    </>
  )
}
