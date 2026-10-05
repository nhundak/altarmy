import { type CSSProperties, Fragment, type ReactNode, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Alert, Badge, Box, Button, Divider, Group, Loader, NumberInput, Paper, Stack, Text, Title, Tooltip, UnstyledButton } from '@mantine/core'
import { LayoutGroup, animate, motion } from 'motion/react'
import { useDebouncedValue } from '@mantine/hooks'
import type { ItemMap, Learn, RankResult } from '../api/client'
import {
  type EvaluateParams,
  type RankParams,
  useDataVersion,
  useRank,
  usePrefetchSessionPlans,
  useSessionPlan,
  useStatus,
  useTrack,
} from '../api/queries'
import { choose as chooseAt, type Choices } from '../lib/choices'
import { layoutTop, scrollTarget } from '../lib/scroll'
import type { Holder } from '../lib/setup'
import { AT_WHICH_POINT, CHEAPER, climbExtra, runLead, runText, scaleRun, stepsText } from '../lib/skill'
import { talentNote } from '../lib/talents'
import type { PlanEditing } from './ChoiceMenu'
import { CharacterClasses, CharacterName } from './CharacterName'
import { ItemLink } from './ItemTooltip'
import { LearnStep, LearnTooltip } from './LearnTooltip'
import { Money } from './Money'
import { SkillBar } from './SkillBar'
import { RecipeFlow } from './RecipeFlow'
import { PlanViewSwitch, type PlanView } from './SessionDetails'
import { Earned, StepList } from './StepList'
import classes from './SkillWorkspace.module.css'

/** The runs asked for at once: Next up, the few after it, and the rest under See all. */
const TOP = 50
/** Options laid out side by side before See all. */
const OPTIONS = 4
// The runs the chain holds at first (the API's `SKILL_CHAIN`), and how many more each Show more asks for
const CHAIN = 4
const NO_RUNS: RankResult[] = []
/** Cards See all shows at first, and how many more each Show more adds. */
const GRID = 20
/** How a chosen option opens out into its run (as the Profit page's cards do). */
const LAYOUT = { duration: 0.3, ease: [0.25, 0.8, 0.25, 1] as const }

type Filters = Omit<RankParams, 'top'>

/** What a run comes to per skill point it is expected to give, its pattern included: gained in green, spent in red
 * with a minus sign. */
function NetPerPoint({ result }: { result: RankResult }) {
  if (!result.skill_ups) return <>no skill point</>
  return (
    <>
      <Earned copper={Math.round((result.profit - (result.learn_cost ?? 0)) / result.skill_ups)} minus /> per skill point
    </>
  )
}

/** A recipe's name. */
function RecipeName({ result, items }: { result: RankResult; items: ItemMap }) {
  return <ItemLink item={items[result.output_item_id]} name={result.output_name} />
}

/** How far to craft and why then, the recipe that gives a cheaper point by then as an item link (icon, its
 * quality's colour, tooltip). */
function RunText({ result: r, items }: { result: RankResult; items: ItemMap }) {
  if (r.stop_reason !== 'rival') return <>{runText(r)}</>
  const rival = r.overtaken_by_item ? items[r.overtaken_by_item] : undefined
  return (
    <>
      {runLead(r)}
      {AT_WHICH_POINT}
      <ItemLink item={rival} name={r.overtaken_by || 'another recipe'} />
      {CHEAPER}
    </>
  )
}

// The size of the spinner beside the odds (px).
const SPINNER = 16
// The most crafts the checklist buys for.
const MAX_BUY = 999

/** The chance, in whole percent (never rounded up), that `crafts` crafts reach the run's `stop_skill`; past the
 * odds the server sent, the last of them. */
function reachPercent(r: RankResult, crafts: number): number {
  const odds = r.reach_chances ?? []
  const chance = odds.length === 0 ? 1 : (odds[Math.min(crafts, odds.length) - 1] ?? 0)
  return Math.floor(chance * 100 + 1e-9)
}

/** Whether the climber must learn a run's recipe first. */
const mustLearn = (r: RankResult): boolean => !!r.crafter && !r.crafters.includes(r.crafter)

/** What the climber must do to learn a run's recipe; null when they know it. */
function learnNote(r: RankResult, learn: Learn | undefined): ReactNode {
  if (!mustLearn(r)) return null
  if (r.learn_cost === null) return 'You must find the pattern (price unknown)'
  if (learn?.source === 'trainer') return 'You must learn it from a trainer'
  if (!r.learn_cost) return 'You must learn it first'
  return (
    <>
      You must buy the pattern (<Money copper={r.learn_cost} />)
    </>
  )
}

/** An option card's last row when the climber lacks the recipe and what learning it costs is counted. */
const TRAIN_NOTE = 'You will need to train this recipe (included in the cost)'

/** "Frell's", "Frell Ofelements'". */
const possessive = (name: string) => (name.endsWith('s') ? `${name}'` : `${name}'s`)

/** One option in the overview: the recipe, what its run comes to per skill point, how far it goes, how it is
 * learned, and (`extra`) what starting with it adds to the whole climb over the best. Without `onChoose`, a summary
 * of a run to come (in the chain), with nothing to click; `fade`: it fades in as the other options open out. */
function OptionCard({
  result: r,
  best,
  items,
  learn,
  extra,
  fade,
  onChoose,
}: {
  result: RankResult
  best: boolean
  items: ItemMap
  learn: Learn | undefined
  extra?: number | null
  fade?: boolean
  onChoose?: () => void
}) {
  const body = (
          <Stack gap={4}>
            <Group justify="space-between" align="flex-start" wrap="nowrap" gap="xs">
              <Text fw={600} size="sm">
                <RecipeName result={r} items={items} />
              </Text>
              {best && (
                <Badge size="xs" variant="light" color="teal" style={{ flexShrink: 0 }}>
                  Best
                </Badge>
              )}
            </Group>
            <Text size="lg" fw={700}>
              <NetPerPoint result={r} />
            </Text>
            <Text size="xs" c="dimmed">
              <RunText result={r} items={items} />
            </Text>
            {/* a recipe the climber lacks: its pattern is counted in the cost, unless nobody can price it */}
            {mustLearn(r) && (
              <Text size="xs" c={r.learn_cost === null ? 'orange' : 'dimmed'}>
                {r.learn_cost === null ? learnNote(r, learn) : TRAIN_NOTE}
              </Text>
            )}
            {/* a run cheaper per point can still make the whole climb dearer: what comes after it costs more */}
            {extra != null && (
              <Text size="xs" c="dimmed">
                The whole climb costs <Money copper={extra} /> more than with the best
              </Text>
            )}
          </Stack>
  )
  if (!onChoose) {
    return (
      <Paper withBorder radius="md" p="sm" component="article" aria-label={r.output_name}>
        {body}
      </Paper>
    )
  }
  return (
    <motion.div
      layoutId={`skill-option-${r.recipe_id}`}
      transition={LAYOUT}
      initial={fade ? { opacity: 0 } : false}
      animate={{ opacity: 1 }}
      style={{ borderRadius: 8 }}
    >
      <Paper withBorder radius="md" p="sm" h="100%" data-best={best || undefined}>
        <UnstyledButton
          onClick={onChoose}
          aria-label={`Choose ${r.output_name}`}
          w="100%"
          h="100%"
          // a button centres its content: cards of three lines and of four start at the same height
          style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-start' }}
        >
          {body}
        </UnstyledButton>
      </Paper>
    </motion.div>
  )
}

/** The short arrow from one run to the run after it. */
function ChainArrow() {
  return (
    <svg className={classes.arrow} width="16" height="24" viewBox="0 0 16 24" aria-hidden>
      <path d="M8 2v18M3 15l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

/** The runs that follow the one crafted now, each under an arrow, hung under that run's card. `muted` while it
 * isn't the chosen option's own yet: the other options are open, or its chain is on its way. `onMore`: Show more
 * under the last, when there may be more after it. */
function Chain({
  runs,
  start,
  items,
  learn,
  muted,
  pending,
  onMore,
}: {
  runs: RankResult[]
  /** the skill the first of `runs` starts at: where the run crafted now stops */
  start: number
  items: ItemMap
  learn: Record<string, Learn>
  muted: boolean
  pending: boolean
  onMore?: () => void
}) {
  if (!runs.length && !pending) return null
  return (
    <motion.section
      layoutId="skill-chain"
      transition={LAYOUT}
      className={classes.chain}
      data-muted={muted || undefined}
      aria-disabled={muted || undefined}
      aria-label="What comes after"
    >
      {runs.map((r, i) => {
        const from = i === 0 ? start : (runs[i - 1]?.stop_skill ?? 0)
        return (
          // a climb may come back to a recipe: keyed by place
          <Stack key={`${i}-${r.recipe_id}`} gap={4}>
            <div className={classes.step}>
              <ChainArrow />
              {from > 0 && (
                <Text size="xs" c="dimmed" className={classes.at}>
                  At {from} skill
                </Text>
              )}
            </div>
            <OptionCard result={r} best={false} items={items} learn={learn[r.recipe_id]} />
          </Stack>
        )
      })}
      {pending && <Loader size="xs" aria-label="Working out what comes after" className={classes.arrow} />}
      {onMore && !pending && (
        <Button size="compact-sm" variant="subtle" className={classes.chainMore} onClick={onMore}>
          Show more
        </Button>
      )}
    </motion.section>
  )
}

/**
 * Skilling up one profession on one character. First an overview: the run to craft now (the first of the cheapest
 * climb up the profession; each option counted as the first run of the cheapest climb starting with it, until the
 * climb goes on with another recipe, it turns trivial or the skill reaches its cap), centred, with the rest of its
 * climb hung below; Show me other options lays
 * the best few side by side, the chain muted under the one it follows until another is picked, which then folds
 * back to be the one crafted now. Choosing the run crafted now opens it out into the full run: what to make until when, what it costs,
 * what the next best was, what comes after it, and a checklist per character to take into the game. The list holds still while new prices come in, until the
 * user refreshes it.
 */
export function SkillWorkspace({
  filters,
  climber,
  profession,
}: {
  filters: Filters
  climber: Holder
  profession: string
}) {
  const track = useTrack()
  const status = useStatus().data
  const livePrices = status?.price_version ?? 0
  // The price version the list was made at: it moves only on Refresh.
  const [frozen, setFrozen] = useState<number | undefined>(undefined)
  if (frozen === undefined && status) setFrozen(livePrices)
  const params = useMemo<RankParams>(() => ({ ...filters, top: TOP }), [filters])
  const rank = useRank(params, { priceVersion: frozen })
  const version = useDataVersion()
  // The option opened out; null: the overview.
  const [openId, setOpenId] = useState<number | null>(null)
  const [all, setAll] = useState(false)
  // How many cards the full list shows; past the ones that came with the list, more are asked for.
  const [shown, setShown] = useState(GRID)
  const results = rank.data?.results ?? []
  const allRank = useRank(
    { ...params, top: shown },
    { priceVersion: frozen, enabled: all && shown > results.length },
  )
  const listed = (shown > results.length ? allRank.data?.results : undefined) ?? results
  // The options side by side: the runs starting the cheapest climbs, each what picking it gives, else as listed.
  const options = rank.data?.options?.length ? rank.data.options : results.slice(0, OPTIONS)
  const bestId = results[0]?.recipe_id
  // The option to craft now: the best unless the user picked another of the first few (null: the best).
  const [pickedId, setPickedId] = useState<number | null>(null)
  const nowIndex = Math.max(
    0,
    options.findIndex((r) => r.recipe_id === pickedId),
  )
  const ranked = options[nowIndex]
  const picked = ranked !== undefined && ranked.recipe_id !== bestId
  // Whether the first few options are laid out side by side, the user choosing among them.
  const [expanded, setExpanded] = useState(false)
  // How many runs the chain holds: CHAIN, and CHAIN more with each Show more (back to CHAIN on a pick).
  const [chainLength, setChainLength] = useState(CHAIN)
  const longer = chainLength > CHAIN
  // A picked option's run and the rest of its climb (the ranking itself is the server's cached one); the best's
  // come with the list, unless more of them are shown.
  const chainRank = useRank(
    { ...params, top: 1, chainFrom: ranked?.recipe_id, chainLength: longer ? chainLength : undefined },
    { priceVersion: frozen, enabled: picked || longer },
  )
  const restart = chainRank.data?.chain_start
  const now = picked && restart?.recipe_id === ranked?.recipe_id ? restart : ranked
  const chainData = picked || longer ? chainRank.data : rank.data
  // The chain on its way: a picked option's (the one shown before it stays, muted) or a longer one.
  const chainPending = (picked || longer) && (chainRank.isPlaceholderData || !chainRank.data)
  const current = chainData?.chain ?? rank.data?.chain ?? NO_RUNS
  // The chain as last settled: what stays shown while a longer one is on its way.
  const [settled, setSettled] = useState(current)
  if (!chainPending && current !== settled) setSettled(current)
  const chain = chainPending && longer ? settled : current
  // the run crafted now as it stands after a pick, else as ranked
  const open =
    openId === null
      ? undefined
      : openId === now?.recipe_id
        ? now
        : (options.find((r) => r.recipe_id === openId) ?? listed.find((r) => r.recipe_id === openId))
  const atCap = climber.rank >= climber.maxRank
  const evaluate: EvaluateParams = {
    unlearned: filters.unlearned,
    lookAhead: filters.lookAhead,
    sources: filters.sources,
    includeTrivial: filters.includeTrivial,
    skillCrafters: filters.skillCrafters,
    exits: filters.exits,
    arcaneSalvager: filters.arcaneSalvager,
    runs: filters.runs,
    version,
  }
  // The crafts the checklist buys for: what the user typed, else enough to reach the run's target four times in
  // five; planned again (debounced) when that isn't the ranked run's own count.
  const [typed, setTyped] = useState<number | null>(null)
  const buyCount = open ? (typed ?? Math.max(open.crafts, open.crafts_p80)) : 0
  const [settledCount] = useDebouncedValue(buyCount, 400)
  // Each option's plan for the crafts it opens with, fetched ahead: opening one finds it ready.
  usePrefetchSessionPlans(
    [...options, ...(now && now !== ranked ? [now] : [])]
      .filter((r) => r.crafts_p80 > r.crafts)
      .map((r) => ({ recipeId: r.recipe_id, copies: r.crafts_p80 })),
    evaluate,
  )
  const buyFor = open && settledCount > 0 && settledCount !== open.crafts ? settledCount : null
  // The user's changes to the run's plan (another source for a reagent, another way to sell); undefined: as ranked.
  const [choices, setChoices] = useState<Choices | undefined>(undefined)
  const modified = choices !== undefined
  const planning = buyFor !== null || modified
  const plan = useSessionPlan(open?.recipe_id ?? 0, evaluate, choices, buyFor, null, null, planning)
  // The server's plan for the count and choices when it has one, else the last plan in proportion, so the
  // quantities follow the count at once.
  const planned = (planning && plan.data?.result) || open
  const checklist = planned && scaleRun(planned, buyCount)
  // The skill points Working Overtime adds to the crafts bought for (the ranked run's until their plan is back).
  const overtime = planned?.skill_ups_bonus ?? 0
  // Planning a count the user typed. The count a run opens with is fetched ahead; should it still be on its way, the
  // ranked run in proportion shows meanwhile, close enough to need no spinner.
  const replanning = typed !== null && plan.isFetching && !modified
  const editing: PlanEditing = {
    onChoose: (paths, key) => setChoices((prev) => paths.reduce((c, path) => chooseAt(c, path, key), prev ?? {})),
    modified,
    onReset: () => setChoices(undefined),
    pending: modified && plan.isFetching,
    error: modified ? (plan.error?.message ?? null) : null,
  }
  const items = useMemo(
    () => ({ ...allRank.data?.items, ...rank.data?.items, ...chainRank.data?.items, ...plan.data?.items }),
    [allRank.data, rank.data, chainRank.data, plan.data],
  )
  useEffect(() => {
    if (bestId !== undefined) track('next_up_shown', { profession })
  }, [bestId, profession, track])

  const [copied, setCopied] = useState(false)
  // The run's plan as its steps (first) or a flow chart.
  const [view, setView] = useState<PlanView>('steps')
  // Scrolls an option being opened out fully into view as it grows: its layout is final as soon as it renders (the
  // growing is a transform), so the scroll runs alongside, with the same timing. A wheel or touch stops it.
  const runRef = useRef<HTMLElement>(null)
  const scrollPending = useRef(false)
  useLayoutEffect(() => {
    const el = runRef.current
    if (openId === null || !scrollPending.current || !el) return
    scrollPending.current = false
    const target = scrollTarget(layoutTop(el), el.offsetHeight, window.scrollY, window.innerHeight)
    if (target === null) return
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      window.scrollTo(0, target)
      return
    }
    const scroll = animate(window.scrollY, target, { ...LAYOUT, onUpdate: (y) => window.scrollTo(0, y) })
    const stop = () => scroll.stop()
    window.addEventListener('wheel', stop, { passive: true })
    window.addEventListener('touchstart', stop, { passive: true })
    return () => {
      scroll.stop()
      window.removeEventListener('wheel', stop)
      window.removeEventListener('touchstart', stop)
    }
  }, [openId])
  const choose = (id: number | null) => {
    setOpenId(id)
    scrollPending.current = id !== null
    setTyped(null)
    setChoices(undefined)
    setView('steps')
    setCopied(false)
    if (id !== null) track('row_opened', { profession })
  }
  const copy = () => {
    if (!checklist) return
    const text = stepsText(`${profession}: ${checklist.output_name}. ${runText(open ?? checklist)}`, checklist.steps)
    void navigator.clipboard?.writeText(text).then(() => setCopied(true))
    track('copy_steps', { profession })
  }

  const header = (
    <Group gap="sm">
      <Text size="sm">
        <CharacterName name={possessive(climber.name)} classFile={climber.classFile} /> {profession}
      </Text>
      <SkillBar rank={climber.rank} maxRank={climber.maxRank} label={`${climber.name}'s ${profession}`} />
      {climber.talents && (
        <Tooltip
          label={
            <Stack gap="xs">
              {climber.talents.map((t) => (
                <div key={t.spellId}>
                  <Text size="sm" fw={700}>
                    {t.name}
                  </Text>
                  <Text size="sm">
                    Rank {t.rank}/{t.maxRank}
                  </Text>
                  <Text size="sm">{talentNote(t)}</Text>
                </div>
              ))}
            </Stack>
          }
          multiline
          w={260}
          withArrow
        >
          <Text size="sm" c="dimmed" style={{ cursor: 'help' }}>
            ({climber.talents.map((t) => `${t.rank}/${t.maxRank} ${t.name}`).join(', ')})
          </Text>
        </Tooltip>
      )}
    </Group>
  )

  if (rank.isPending) return <Loader />
  if (rank.isError) return <Alert color="red">{rank.error.message}</Alert>
  const learn = { ...allRank.data?.learn, ...rank.data.learn }
  const refresh = frozen !== undefined && livePrices !== frozen && (
    <Alert color="blue" title="Prices updated since this list was made">
      <Group justify="space-between">
        <Text size="sm">The list holds still while you work through it.</Text>
        <Button size="xs" variant="light" onClick={() => setFrozen(livePrices)}>
          Refresh
        </Button>
      </Group>
    </Alert>
  )
  const capCard = atCap && (
    <Alert color="orange" title={`You're at your ${profession} cap (${climber.maxRank})`}>
      Visit a {profession} trainer to learn the next rank, then /reload so Alt Army Sync uploads it.
    </Alert>
  )
  if (!results.length) {
    return (
      <Stack>
        {header}
        {capCard}
        {refresh}
        {!atCap && <Alert>Nothing gives {climber.name} a {profession} point with the current prices.</Alert>}
      </Stack>
    )
  }

  // Picking one of the options side by side makes it the one to craft now, the others folding away around it.
  const pick = (id: number) => {
    setPickedId(id === bestId ? null : id)
    setChainLength(CHAIN)
    setExpanded(false)
    setAll(false)
  }
  const chainView = (
    <Chain
      runs={chain}
      start={now?.stop_skill ?? 0}
      items={items}
      learn={{ ...learn, ...chainRank.data?.learn }}
      // a longer chain on its way keeps the runs already shown as they are
      muted={expanded || (chainPending && !longer)}
      pending={chainPending && !expanded}
      onMore={!expanded && chain.length >= chainLength ? () => setChainLength((n) => n + CHAIN) : undefined}
    />
  )

  return (
    <CharacterClasses.Provider value={rank.data.classes}>
      <Stack>
        {header}
        {capCard}
        {refresh}
        <LayoutGroup>
          {open ? (
            // grows out of its option card; opened from the full list, which has none, it fades in
            <motion.div
              layoutId={`skill-option-${open.recipe_id}`}
              transition={LAYOUT}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              style={{ borderRadius: 8 }}
            >
              <Paper ref={runRef} withBorder p="md" radius="md" aria-label="Run details" component="section">
                <Stack gap="xs">
                  <Group justify="space-between">
                    <Button size="compact-sm" variant="subtle" onClick={() => choose(null)}>
                      ← All options
                    </Button>
                    <Group gap={6}>
                      {modified && (
                        <Badge size="sm" variant="light" color="yellow">
                          Changed plan
                        </Badge>
                      )}
                      {open.recipe_id === bestId && (
                        <Badge size="sm" variant="light" color="teal">
                          Best
                        </Badge>
                      )}
                    </Group>
                  </Group>
                  <Title order={4}>
                    <RecipeName result={open} items={items} />
                  </Title>
                  <Text size="lg" fw={700}>
                    {/* the user's changed plan costs what it costs; otherwise the run as ranked */}
                    <NetPerPoint result={(modified && planned) || open} />
                  </Text>
                  <Text size="sm">
                    <RunText result={open} items={items} />
                  </Text>
                  {learn[open.recipe_id] && mustLearn(open) && (
                    <Text size="sm">
                      {learnNote(open, learn[open.recipe_id])}:{' '}
                      <LearnTooltip learn={learn[open.recipe_id]}>where to get it</LearnTooltip>
                    </Text>
                  )}
                  <Divider my={4} />
                  {open.stop_skill > 0 && (
                    <Group gap="xs" wrap="nowrap">
                      <NumberInput
                        size="xs"
                        w={90}
                        min={1}
                        max={MAX_BUY}
                        allowDecimal={false}
                        aria-label="Crafts to buy for"
                        value={buyCount}
                        onChange={(v) => setTyped(typeof v === 'number' && v >= 1 ? Math.min(v, MAX_BUY) : null)}
                      />
                      <Text size="xs" c="dimmed">
                        {reachPercent(open, buyCount)}% chance to reach your target of {open.stop_skill} skill
                        {overtime >= 0.05 && ` (includes ~${overtime.toFixed(1)} skill points from Working Overtime)`}
                      </Text>
                      {/* A slot of its own size, so the spinner never moves anything */}
                      <Box w={SPINNER} h={SPINNER} style={{ flexShrink: 0 }}>
                        {replanning && <Loader size={SPINNER} aria-label="Planning" />}
                      </Box>
                    </Group>
                  )}
                  <Group gap="sm">
                    <PlanViewSwitch value={view} onChange={setView} />
                    {modified && (
                      <Button size="compact-xs" variant="light" onClick={editing.onReset}>
                        Reset
                      </Button>
                    )}
                    {editing.pending && <Loader size="xs" aria-label="Re-costing" />}
                    {editing.error && (
                      <Text size="xs" c="red">
                        {editing.error}
                      </Text>
                    )}
                  </Group>
                  {checklist &&
                    (view === 'flow' ? (
                      <RecipeFlow result={checklist} items={items} editing={editing} />
                    ) : (
                      <StepList
                        result={checklist}
                        items={items}
                        editing={editing}
                        mode="skill"
                        learn={
                          learn[open.recipe_id] &&
                          mustLearn(open) && (
                            <LearnStep
                              learn={learn[open.recipe_id]!}
                              recipe={open.output_name}
                              cost={open.learn_cost}
                              items={items}
                            />
                          )
                        }
                      />
                    ))}
                  <Group gap="xs">
                    <Button size="xs" variant="light" onClick={copy}>
                      {copied ? 'Copied' : 'Copy steps'}
                    </Button>
                  </Group>
                </Stack>
              </Paper>
            </motion.div>
          ) : (
            <Stack gap="xs" component="section" aria-label="Your options">
              <Text size="lg" fw={600} ta="center">
                What to craft next:
              </Text>
              {expanded && all ? (
                // every option as a card, opened straight into its run; no chain here
                <Stack gap="xs" aria-label="All options">
                  <Group justify="flex-end">
                    <Button variant="subtle" size="xs" onClick={() => setAll(false)}>
                      Hide the full list
                    </Button>
                  </Group>
                  <div className={classes.grid}>
                    {listed.slice(0, shown).map((r) => (
                      <OptionCard
                        key={r.recipe_id}
                        result={r}
                        best={r.recipe_id === bestId}
                        items={items}
                        learn={learn[r.recipe_id]}
                        extra={climbExtra(r, results[0])}
                        onChoose={() => choose(r.recipe_id)}
                      />
                    ))}
                  </div>
                  {shown < rank.data.total && (
                    <Button
                      variant="light"
                      size="xs"
                      style={{ alignSelf: 'center' }}
                      loading={allRank.isFetching}
                      onClick={() => setShown((n) => n + GRID)}
                    >
                      Show more
                    </Button>
                  )}
                </Stack>
              ) : expanded ? (
                <div
                  className={classes.options}
                  style={
                    {
                      '--options': options.length,
                      '--now': nowIndex + 1,
                      // under the rightmost card, below the chain should it hang there too
                      '--see-all-row': nowIndex === options.length - 1 ? 3 : 2,
                    } as CSSProperties
                  }
                >
                  {options.map((r) => (
                    <Fragment key={r.recipe_id}>
                      <OptionCard
                        result={r}
                        best={r.recipe_id === bestId}
                        items={items}
                        learn={learn[r.recipe_id]}
                        extra={climbExtra(r, results[0])}
                        fade={r.recipe_id !== now?.recipe_id}
                        onChoose={() => pick(r.recipe_id)}
                      />
                      {r.recipe_id === now?.recipe_id && chainView}
                    </Fragment>
                  ))}
                  {results.length > OPTIONS && (
                    <Button
                      variant="subtle"
                      size="xs"
                      className={classes.seeAll}
                      onClick={() => {
                        setShown(GRID)
                        setAll(true)
                      }}
                    >
                      See all {rank.data.total} options
                    </Button>
                  )}
                </div>
              ) : (
                now && (
                  <div className={classes.single}>
                    <div className={classes.now}>
                      <OptionCard
                        result={now}
                        best={now.recipe_id === bestId}
                        items={items}
                        learn={learn[now.recipe_id]}
                        // picked over the best: what that adds to the whole climb stays said
                        extra={climbExtra(now, results[0])}
                        onChoose={() => choose(now.recipe_id)}
                      />
                    </div>
                    {options.length > 1 && (
                      <Button variant="subtle" size="xs" className={classes.more} onClick={() => setExpanded(true)}>
                        Show me other options
                      </Button>
                    )}
                    {chainView}
                  </div>
                )
              )}
            </Stack>
          )}
        </LayoutGroup>
      </Stack>
    </CharacterClasses.Provider>
  )
}
