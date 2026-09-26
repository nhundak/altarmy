import { useState } from 'react'
import { Button, Checkbox, Group, Loader, NumberInput, SegmentedControl, Select, Stack, Text } from '@mantine/core'
import { useDebouncedValue } from '@mantine/hooks'
import { z } from 'zod'
import type { ItemMap, RankResult } from '../api/client'
import { useSessionPlan, useTime, type EvaluateParams } from '../api/queries'
import type { Choices } from '../lib/choices'
import { formatMoney } from '../lib/money'
import { useStoredState } from '../lib/storage'
import { formatSeconds } from '../lib/time'
import type { PlanEditing } from './ChoiceMenu'
import { Money } from './Money'
import { RecipeFlow } from './RecipeFlow'
import { Earned, StepList } from './StepList'
import { TimingNotes } from './TimingSummary'

/** Copies when the time settings haven't loaded (their own default). */
const FALLBACK_COPIES = 20
const MAX_COPIES = 1000

type View = 'flow' | 'steps'

/** Each city with what this session makes per hour there (once planned), or the station it lacks. */
function cityOptions(cities: string[], session: RankResult | undefined) {
  const timed = new Map(session?.cities.map((c) => [c.city, c]))
  return cities.map((name) => {
    const c = timed.get(name)
    if (!c) return { value: name, label: name }
    const note = c.missing.length
      ? `no ${c.missing.map((k) => k.replaceAll('_', ' ')).join(' or ')}`
      : `${formatMoney(c.per_hour)}/hr`
    return { value: name, label: `${name} (${note})` }
  })
}

/** The session's crafts, cost, profit, time and rate. */
function Summary({ result }: { result: RankResult }) {
  const t = result.timing
  return (
    <Text size="sm">
      {result.crafts} {result.crafts === 1 ? 'craft' : 'crafts'}: cost <Money copper={result.cost} cost /> · profit{' '}
      <Earned copper={result.profit} />
      {t && (
        <>
          {' '}
          · {formatSeconds(t.total_seconds)} · <Earned copper={t.per_hour} />
          /hr
        </>
      )}
    </Text>
  )
}

/**
 * An expanded row: the plan for a session of `copies` crafts in a city, as the server works it out (whole
 * batches, whole stacks, the route), as a flow chart or steps (optionally with where to go in between).
 * One Reset brings back the best plan, the default copies and the default city. Until the session is
 * planned (or if planning fails) the row's own plan shows.
 */
export function SessionDetails({
  result,
  items,
  editing,
  params,
  choices,
}: {
  result: RankResult
  items: ItemMap
  editing: PlanEditing
  params: EvaluateParams
  choices: Choices | undefined
}) {
  const [view, setView] = useState<View>('flow')
  const settings = useTime().data
  const cities = settings?.cities.map((c) => c.name) ?? []
  const defaultCopies = settings?.config.batch ?? FALLBACK_COPIES
  const timedIn = result.timing?.city
  const defaultCity = timedIn && cities.includes(timedIn) ? timedIn : (cities[0] ?? null)
  const [copies, setCopies] = useState<number | null>(null) // null: the default
  const [city, setCity] = useState<string | null>(null)
  const [detailed, setDetailed] = useStoredState('altarmy-profit.steps.detailed', z.boolean(), false)
  const shownCopies = copies ?? defaultCopies
  const shownCity = city ?? defaultCity
  const [debouncedCopies] = useDebouncedValue(shownCopies, 400)
  const plan = useSessionPlan(result.recipe_id, params, choices, debouncedCopies, shownCity)
  const session = plan.data?.result
  const shown = session ?? result
  const shownItems = { ...items, ...plan.data?.items }
  const changed =
    editing.modified || (copies !== null && copies !== defaultCopies) || (city !== null && city !== defaultCity)
  const reset = () => {
    setCopies(null)
    setCity(null)
    if (editing.modified) editing.onReset()
  }
  return (
    <Stack gap="xs" py="xs">
      <Group gap="sm" align="flex-end">
        <SegmentedControl
          size="xs"
          mb={2}
          value={view}
          onChange={(v) => setView(v as View)}
          data={[
            { value: 'flow', label: 'Flow' },
            { value: 'steps', label: 'Steps' },
          ]}
        />
        <NumberInput
          label="Copies"
          size="xs"
          w={110}
          min={1}
          max={MAX_COPIES}
          allowDecimal={false}
          value={shownCopies}
          onChange={(v) => typeof v === 'number' && v >= 1 && setCopies(Math.min(Math.round(v), MAX_COPIES))}
        />
        {cities.length > 0 && (
          <Select
            label="City"
            size="xs"
            w={230}
            data={cityOptions(cities, session)}
            value={shownCity}
            onChange={(v) => v && setCity(v)}
            allowDeselect={false}
          />
        )}
        {view === 'steps' && (
          <Checkbox
            label="Detailed view"
            size="xs"
            mb={6}
            checked={detailed}
            onChange={(e) => setDetailed(e.currentTarget.checked)}
          />
        )}
        {changed && (
          <Button size="compact-xs" variant="light" mb={4} onClick={reset}>
            Reset
          </Button>
        )}
        {editing.pending && <Loader size="xs" mb={6} aria-label="Re-costing" />}
        {plan.isFetching && !editing.pending && <Loader size="xs" mb={6} aria-label="Planning" />}
        {(editing.error || plan.error) && (
          <Text size="xs" c="red" mb={6}>
            {editing.error ?? plan.error?.message}
          </Text>
        )}
      </Group>
      <Summary result={shown} />
      {view === 'flow' ? (
        <RecipeFlow result={shown} items={shownItems} editing={editing} />
      ) : (
        <StepList result={shown} items={shownItems} editing={editing} detailed={detailed} />
      )}
      <TimingNotes result={shown} items={shownItems} />
    </Stack>
  )
}
