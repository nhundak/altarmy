import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Alert, Badge, Button, Divider, Group, Loader, NumberInput, Paper, SimpleGrid, Stack, Text, Title, UnstyledButton } from '@mantine/core'
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
import { layoutTop, scrollTarget } from '../lib/scroll'
import type { Holder } from '../lib/setup'
import { AT_WHICH_POINT, CHEAPER, runLead, runText, scaleRun, stepsText } from '../lib/skill'
import { CharacterName } from './CharacterName'
import { ItemLink } from './ItemTooltip'
import { LearnTooltip } from './LearnTooltip'
import { ResultsTable } from './ResultsTable'
import { SkillBar } from './SkillBar'
import { Earned, StepList } from './StepList'

/** The runs asked for at once: Next up, the few after it, and the rest under See all. */
const TOP = 50
/** Options laid out side by side before See all. */
const OPTIONS = 4
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

// The most crafts the checklist buys for.
const MAX_BUY = 999

/** The chance, in whole percent (never rounded up), that `crafts` crafts reach the run's `stop_skill`; past the
 * odds the server sent, the last of them. */
function reachPercent(r: RankResult, crafts: number): number {
  const odds = r.reach_chances ?? []
  const chance = odds.length === 0 ? 1 : (odds[Math.min(crafts, odds.length) - 1] ?? 0)
  return Math.floor(chance * 100 + 1e-9)
}

/** What the climber must do to learn a run's recipe; null when they know it. */
function learnNote(r: RankResult, learn: Learn | undefined): string | null {
  if (!r.crafter || r.crafters.includes(r.crafter)) return null
  if (r.learn_cost === null) return 'You must find the pattern (price unknown)'
  if (learn?.source === 'trainer') return 'You must learn it from a trainer'
  return r.learn_cost ? 'You must buy the pattern (cost included)' : 'You must learn it first'
}

/** "Frell's", "Frell Ofelements'". */
const possessive = (name: string) => (name.endsWith('s') ? `${name}'` : `${name}'s`)

/** One option in the overview: the recipe, what its run comes to per skill point, how far it goes, how it is
 * learned. */
function OptionCard({
  result: r,
  best,
  items,
  learn,
  onChoose,
}: {
  result: RankResult
  best: boolean
  items: ItemMap
  learn: Learn | undefined
  onChoose: () => void
}) {
  return (
    <motion.div layoutId={`skill-option-${r.recipe_id}`} transition={LAYOUT} style={{ borderRadius: 8 }}>
      <Paper withBorder radius="md" p="sm" h="100%" data-best={best || undefined}>
        <UnstyledButton
          onClick={onChoose}
          aria-label={`Choose ${r.output_name}`}
          w="100%"
          h="100%"
          // a button centres its content: cards of three lines and of four start at the same height
          style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-start' }}
        >
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
            {learnNote(r, learn) && (
              <Text size="xs" c={r.learn_cost === null ? 'orange' : 'dimmed'}>
                {learnNote(r, learn)}
              </Text>
            )}
          </Stack>
        </UnstyledButton>
      </Paper>
    </motion.div>
  )
}

/**
 * Skilling up one profession on one character. First an overview: the few best options side by side, the cheapest
 * skill point on the left, each counted as a run (the crafts until another recipe would give a cheaper skill point,
 * it turns trivial or the skill reaches its cap). Choosing one opens it out into the full run: what to make until when, what it costs,
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
  const results = rank.data?.results ?? []
  const open = openId === null ? undefined : results.find((r) => r.recipe_id === openId)
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
    results
      .slice(0, OPTIONS)
      .filter((r) => r.crafts_p80 > r.crafts)
      .map((r) => ({ recipeId: r.recipe_id, copies: r.crafts_p80 })),
    evaluate,
  )
  const buyFor = open && settledCount > 0 && settledCount !== open.crafts ? settledCount : null
  const plan = useSessionPlan(open?.recipe_id ?? 0, evaluate, undefined, buyFor, null, null, buyFor !== null)
  // The server's plan for the count when it has one, else the last plan in proportion, so the quantities follow
  // the count at once.
  const planned = (buyFor !== null && plan.data?.result) || open
  const checklist = planned && scaleRun(planned, buyCount)
  const items = useMemo(() => ({ ...rank.data?.items, ...plan.data?.items }), [rank.data, plan.data])

  const bestId = results[0]?.recipe_id
  useEffect(() => {
    if (bestId !== undefined) track('next_up_shown', { profession })
  }, [bestId, profession, track])

  const [copied, setCopied] = useState(false)
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
      {climber.workingOvertime && (
        <Text size="sm" c="dimmed">
          ({climber.workingOvertime.rank}/{climber.workingOvertime.maxRank} Working Overtime)
        </Text>
      )}
      {open?.stop_skill ? (
        <Text size="sm" c="dimmed">
          → about {open.stop_skill} after this run
        </Text>
      ) : null}
    </Group>
  )

  if (rank.isPending) return <Loader />
  if (rank.isError) return <Alert color="red">{rank.error.message}</Alert>
  const { learn } = rank.data
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

  const options = results.slice(0, OPTIONS)

  return (
    <Stack>
      {header}
      {capCard}
      {refresh}
      <LayoutGroup>
        {open ? (
          <motion.div layoutId={`skill-option-${open.recipe_id}`} transition={LAYOUT} style={{ borderRadius: 8 }}>
            <Paper ref={runRef} withBorder p="md" radius="md" aria-label="Run details" component="section">
              <Stack gap="xs">
                <Group justify="space-between">
                  <Button size="compact-sm" variant="subtle" onClick={() => choose(null)}>
                    ← All options
                  </Button>
                  {open.recipe_id === bestId && (
                    <Badge size="sm" variant="light" color="teal">
                      Best
                    </Badge>
                  )}
                </Group>
                <Title order={4}>
                  <RecipeName result={open} items={items} />
                </Title>
                <Text size="lg" fw={700}>
                  <NetPerPoint result={open} />
                </Text>
                <Text size="sm">
                  <RunText result={open} items={items} />
                  {open.skill_ups_bonus >= 0.05 && ` · ${open.skill_ups_bonus.toFixed(1)} points from Working Overtime`}
                </Text>
                {learn[open.recipe_id] && !open.crafters.includes(open.crafter) && (
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
                    </Text>
                    {plan.isFetching && <Loader size="xs" aria-label="Planning" />}
                  </Group>
                )}
                {checklist && <StepList result={checklist} items={items} mode="skill" />}
                {plan.isFetching && open.stop_skill === 0 && <Loader size="xs" aria-label="Planning" />}
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
            <Text size="sm" fw={500}>
              What to craft next:
            </Text>
            <SimpleGrid cols={{ base: 1, xs: 2, md: OPTIONS }} spacing="sm">
              {options.map((r) => (
                <OptionCard
                  key={r.recipe_id}
                  result={r}
                  best={r.recipe_id === bestId}
                  items={items}
                  learn={learn[r.recipe_id]}
                  onChoose={() => choose(r.recipe_id)}
                />
              ))}
            </SimpleGrid>
          </Stack>
        )}
      </LayoutGroup>
      {!open && results.length > OPTIONS && (
        <Button variant="subtle" size="xs" style={{ alignSelf: 'flex-start' }} onClick={() => setAll((a) => !a)}>
          {all ? 'Hide the full list' : `See all ${rank.data.total} options`}
        </Button>
      )}
      {!open && all && (
        <ResultsTable
          results={results}
          items={items}
          classes={rank.data.classes}
          learn={learn}
          params={evaluate}
          rankBy="skill"
        />
      )}
    </Stack>
  )
}
