import { useContext, useState } from 'react'
import { Button, Checkbox, Group, Loader, NumberInput, SegmentedControl, Select, Stack, Text } from '@mantine/core'
import { useDebouncedValue } from '@mantine/hooks'
import { z } from 'zod'
import type { ItemMap, RankResult } from '../api/client'
import { useSessionPlan, type EvaluateParams } from '../api/queries'
import type { Choices } from '../lib/choices'
import { useStoredState } from '../lib/storage'
import type { PlanEditing } from './ChoiceMenu'
import { CharacterClasses, CharacterName } from './CharacterName'
import nameClasses from './CharacterName.module.css'
import { Money } from './Money'
import { RecipeFlow } from './RecipeFlow'
import { Earned, StepList } from './StepList'
import { MarketPanel } from './MarketPanel'
import { TimingNotes } from './TimingSummary'

const MAX_COPIES = 1000

/** How a plan shows: its flow chart or its steps. */
export type PlanView = 'flow' | 'steps'

/** The switch between a plan's flow chart and its steps. It stands out (the primary colour, a size up): it changes
 * the whole panel below. */
export function PlanViewSwitch({ value, onChange }: { value: PlanView; onChange: (view: PlanView) => void }) {
  return (
    <SegmentedControl
      aria-label="Show the plan as"
      size="sm"
      radius="md"
      color="gold"
      fw={600}
      style={{ alignSelf: 'flex-start' }}
      value={value}
      onChange={(v) => onChange(v as PlanView)}
      data={[
        { value: 'steps', label: 'Steps' },
        { value: 'flow', label: 'Flowchart' },
      ]}
    />
  )
}

/** Expected skill points to one decimal, without a trailing ".0". */
const formatSkillUps = (n: number) => String(Math.round(n * 10) / 10)

/** The session's crafts, investment and profit; then the crafter's expected skill points (unknown without
 * characters, so not shown), with the part Working Overtime adds. */
function Summary({ result }: { result: RankResult }) {
  return (
    <Stack gap={2}>
      <Text size="sm">
        {result.crafts} {result.crafts === 1 ? 'craft' : 'crafts'}: Investment <Money copper={result.cost} cost /> · Net
        profit <Earned copper={result.profit} minus />
      </Text>
      {result.crafter && (
        <Text size="sm">
          Estimated skill points gained: {formatSkillUps(result.skill_ups)}
          {formatSkillUps(result.skill_ups_bonus) !== '0' &&
            ` (including ${formatSkillUps(result.skill_ups_bonus)} from Working Overtime)`}
        </Text>
      )}
    </Stack>
  )
}

/**
 * An expanded row: the plan for a session of `copies` crafts, as the server works it out (whole batches, whole
 * stacks, the route), as a flow chart or steps (optionally with where to go in between). The row's own result
 * already is the session of the settings' batch, so it shows at once; only other copies or another crafter are
 * planned again (until then, or if that fails, the row's plan shows). One Reset brings back the best plan, the
 * default copies and crafter. The city is the server's pick: there is no choosing one here.
 */
export function SessionDetails({
  result,
  items,
  editing,
  params,
  choices,
  market = false,
}: {
  result: RankResult
  items: ItemMap
  editing: PlanEditing
  params: EvaluateParams
  choices: Choices | undefined
  /** a gold list's row: Why this? (the market for what is sold) comes first */
  market?: boolean
}) {
  const [view, setView] = useState<PlanView>('steps')
  const defaultCopies = result.crafts
  const [copies, setCopies] = useState<number | null>(null) // null: the default
  const [crafter, setCrafter] = useState<string | null>(null)
  const colours = useContext(CharacterClasses)
  // Who could do the final craft, the one ranked first; a pick only when there is a choice.
  const crafters = result.crafter ? [...new Set([result.crafter, ...result.crafters])] : []
  const [detailed, setDetailed] = useStoredState('altarmy-profit.steps.detailed', z.boolean(), false)
  // What differs from the row's own plan (null: as ranked); typed copies wait for the typing to stop.
  const wantedCopies = copies !== null && copies !== defaultCopies ? copies : null
  const wantedCrafter = crafter !== null && crafter !== result.crafter ? crafter : null
  const [debouncedCopies] = useDebouncedValue(wantedCopies, 400)
  const planCopies = wantedCopies === null ? null : debouncedCopies // back to the default at once
  const custom = planCopies !== null || wantedCrafter !== null
  const plan = useSessionPlan(result.recipe_id, params, choices, planCopies, null, wantedCrafter, custom)
  const session = custom ? plan.data?.result : undefined
  const shown = session ?? result
  const shownItems = session ? { ...items, ...plan.data?.items } : items
  const shownCopies = copies ?? defaultCopies
  const shownCrafter = crafter ?? result.crafter
  const changed = editing.modified || wantedCopies !== null || wantedCrafter !== null
  const reset = () => {
    setCopies(null)
    setCrafter(null)
    if (editing.modified) editing.onReset()
  }
  return (
    <Stack gap="xs" py="xs">
      <Group gap="sm" align="flex-end">
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
        {crafters.length > 1 && (
          <Select
            label="Crafter"
            size="xs"
            w={170}
            data={crafters}
            value={shownCrafter}
            onChange={(v) => v && setCrafter(v)}
            allowDeselect={false}
            renderOption={({ option }) => <CharacterName name={option.value} />}
            classNames={{ input: nameClasses.name }}
            data-class={colours[shownCrafter]}
          />
        )}
        {changed && (
          <Button size="compact-xs" variant="light" mb={4} onClick={reset}>
            Reset
          </Button>
        )}
        {editing.pending && <Loader size="xs" mb={6} aria-label="Re-costing" />}
        {custom && plan.isFetching && !editing.pending && <Loader size="xs" mb={6} aria-label="Planning" />}
        {(editing.error || (custom && plan.error)) && (
          <Text size="xs" c="red" mb={6}>
            {editing.error ?? plan.error?.message}
          </Text>
        )}
      </Group>
      {market && <MarketPanel result={shown} items={shownItems} />}
      <Summary result={shown} />
      <PlanViewSwitch value={view} onChange={setView} />
      {view === 'steps' && (
        <Checkbox
          label="Detailed view"
          size="xs"
          checked={detailed}
          onChange={(e) => setDetailed(e.currentTarget.checked)}
        />
      )}
      {view === 'flow' ? (
        <RecipeFlow result={shown} items={shownItems} editing={editing} />
      ) : (
        <StepList result={shown} items={shownItems} editing={editing} detailed={detailed} />
      )}
      <TimingNotes result={shown} items={shownItems} />
    </Stack>
  )
}
