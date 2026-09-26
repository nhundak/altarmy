import { Fragment, useMemo, useState, type ReactNode } from 'react'
import {
  ActionIcon,
  Button,
  Group,
  List,
  Loader,
  Menu,
  SegmentedControl,
  Stack,
  Table,
  Text,
  UnstyledButton,
} from '@mantine/core'
import type { ItemMap, RankResult, Step } from '../api/client'
import { useEvaluations, type EvaluateParams } from '../api/queries'
import { choose, SELL_PATH, type Choices } from '../lib/choices'
import { formatRoi } from '../lib/money'
import { stepSource } from '../lib/steps'
import { bonusNote, discountNote } from '../lib/talents'
import { CharacterClasses, CharacterName } from './CharacterName'
import { ChoiceMenu, ChooseContext, sellChoices, sourceChoices, type PlanEditing } from './ChoiceMenu'
import { DisenchantHover, ItemLink, RecipeTooltip } from './ItemTooltip'
import { Money } from './Money'
import { RecipeFlow } from './RecipeFlow'
import classes from './ResultsTable.module.css'

const COLUMNS = ['', 'Profit', 'ROI', 'Recipe', 'Profession', 'Crafter', 'Cost', 'Revenue', 'Sell via']
/** Sell via column text per exit; unknown exits show as-is. */
const EXIT_LABELS: Readonly<Record<string, string>> = { ah: 'auction' }
const exitLabel = (exit: string): string => EXIT_LABELS[exit] ?? exit
/** Sort key per sortable column; numbers sort largest first on the first click, text alphabetically. */
const SORT_KEYS: Readonly<Record<string, (r: RankResult) => number | string>> = {
  Profit: (r) => r.profit,
  ROI: (r) => r.roi,
  Recipe: (r) => r.output_name,
  Profession: (r) => r.profession,
  Crafter: (r) => (r.crafters.length ? r.crafter : ''),
  Cost: (r) => r.cost,
  Revenue: (r) => r.revenue,
  'Sell via': (r) => exitLabel(r.best_exit),
}
const NUMERIC_COLUMNS: ReadonlySet<string> = new Set(['Profit', 'ROI', 'Cost', 'Revenue'])
/** Money columns: fixed width, room for -99g 99s 99c on one line (larger amounts drop copper, then silver). */
const MONEY_COLUMNS: ReadonlySet<string> = new Set(['Profit', 'Cost', 'Revenue'])
const MONEY_WIDTH = 110
/** Widths (px) for columns that should not just fit their content: crafter lists wrap, money never does. */
const COLUMN_WIDTHS: Readonly<Record<string, number>> = {
  Crafter: 219,
  Profit: MONEY_WIDTH,
  Cost: MONEY_WIDTH,
  Revenue: MONEY_WIDTH,
}
/** Columns dropped as the screen narrows (ResultsTable.module.css): Profession first, then Cost and Revenue,
 * Crafter, and Sell via last. */
const COLUMN_HIDDEN: Readonly<Record<string, string | undefined>> = {
  Profession: classes.hideBelowLg,
  Cost: classes.hideBelowMd,
  Revenue: classes.hideBelowMd,
  Crafter: classes.hideBelowSm,
  'Sell via': classes.hideBelowXs,
}

type Sort = { column: string; descending: boolean }

/** `results` ordered by `sort`, stably; unsorted keeps the server's order (profit, best first). */
function sorted(results: RankResult[], sort: Sort | null): RankResult[] {
  if (!sort) return results
  const key = SORT_KEYS[sort.column]
  const sign = sort.descending ? -1 : 1
  return results.toSorted((a, b) => {
    const x = key(a)
    const y = key(b)
    const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))
    return sign * c
  })
}

/** A step's amount: spending is a cost (red, unsigned), income is a signed gain. */
const StepMoney = ({ value }: { value: number }) =>
  value < 0 ? <Money copper={-value} cost /> : <Money copper={value} signed />

/** Money made, green or (a loss) red, without a sign. */
const Earned = ({ copper }: { copper: number }) => (
  <Text span inherit c={copper < 0 ? 'red' : 'teal'}>
    <Money copper={Math.abs(copper)} />
  </Text>
)

/** A sale's gross and the recipe's net profit. */
const Sale = ({ gross, net }: { gross: number; net: number }) => (
  <>
    (Gross <Earned copper={gross} /> · Net <Earned copper={net} />)
  </>
)

/** A step as one or more instruction lines, prefixed with who does it; disenchanting splits into disenchant,
 * then sell the mats. */
function describe(step: Step, result: RankResult, items: ItemMap): ReactNode[] {
  const lines = describeAction(step, result, items)
  return step.who
    ? lines.map((l) => (
        <>
          <CharacterName name={step.who} />: {l}
        </>
      ))
    : lines
}

function describeAction(
  { action, item_id, name, quantity, value, via, discount, bonus }: Step,
  result: RankResult,
  items: ItemMap,
): ReactNode[] {
  const item = <ItemLink item={items[item_id]} name={name} />
  const discounted = discountNote(discount)
  const extra = bonus > 0 ? ` (${bonusNote(bonus)})` : ''
  switch (action) {
    case 'buy':
      return [
        <>
          Purchase {quantity}x {item} {via === 'vendor' ? 'from a vendor' : 'on the AH'} (<StepMoney value={value} />
          {discounted && `, ${discounted}`})
        </>,
      ]
    case 'craft':
      return [
        <>
          Craft {quantity}x {item}
        </>,
      ]
    case 'mail':
      return [
        <>
          Mail {quantity}x {item} to <CharacterName name={via} /> (<StepMoney value={value} />)
        </>,
      ]
    case 'sell':
      if (via === 'disenchant')
        return [
          <>
            Disenchant {quantity > 1 ? `${quantity}x ` : ''}
            {item}
            {extra}
          </>,
          <>
            <DisenchantHover result={result} items={items}>
              Sell materials
            </DisenchantHover>{' '}
            <Sale gross={value} net={result.profit} />
          </>,
        ]
      return [
        <>
          Sell {quantity}x {item}
          {extra} {via === 'ah' ? 'on the AH' : 'to a vendor'}{' '}
          <Sale gross={value} net={result.profit} />
        </>,
      ]
  }
}

/** The menu changing how a step is done, if it has alternatives: a reagent's source, or the way to sell. */
function StepChoice({ step, result }: { step: Step; result: RankResult }) {
  if (step.action === 'sell')
    return (
      <ChoiceMenu
        label="Change how it is sold"
        paths={[SELL_PATH]}
        choices={sellChoices(result.sell_options, result.best_exit)}
      />
    )
  const source = stepSource(step, result.tree)
  if (!source) return null
  return (
    <ChoiceMenu
      label={`Change source of ${step.name}`}
      paths={source.paths}
      choices={sourceChoices(source.options, source.option, source.holder)}
    />
  )
}

/** The plan as numbered instructions; with `editing`, a step with alternatives ends in a menu of them. */
function StepList({ result, items, editing }: { result: RankResult; items: ItemMap; editing?: PlanEditing }) {
  const lines = result.steps.flatMap((step) =>
    describe(step, result, items).map((line, i, all) =>
      i < all.length - 1 ? (
        line
      ) : (
        <>
          {line}
          <span className={classes.stepChoice}>
            <StepChoice step={step} result={result} />
          </span>
        </>
      ),
    ),
  )
  return (
    <ChooseContext.Provider value={editing?.onChoose}>
      <List type="ordered" size="sm">
        {lines.map((line, i) => (
          <List.Item key={i}>{line}</List.Item>
        ))}
      </List>
    </ChooseContext.Provider>
  )
}

/** The characters who know the recipe, the one doing the craft first. */
const byCrafter = (crafters: string[], crafter: string) =>
  crafters.includes(crafter) ? [crafter, ...crafters.filter((c) => c !== crafter)] : crafters

type View = 'flow' | 'steps'

function Details({ result, items, editing }: { result: RankResult; items: ItemMap; editing: PlanEditing }) {
  const [view, setView] = useState<View>('flow')
  return (
    <Stack gap="xs" py="xs">
      <Group justify="space-between" gap="xs">
        <SegmentedControl
          size="xs"
          value={view}
          onChange={(v) => setView(v as View)}
          data={[
            { value: 'flow', label: 'Flow' },
            { value: 'steps', label: 'Steps' },
          ]}
        />
        {(editing.modified || editing.error) && (
          <Group gap="xs">
            {editing.pending && <Loader size="xs" aria-label="Re-costing" />}
            {editing.error && (
              <Text size="xs" c="red">
                {editing.error}
              </Text>
            )}
            <Button size="compact-xs" variant="light" onClick={editing.onReset}>
              Reset
            </Button>
          </Group>
        )}
      </Group>
      {view === 'flow' ? (
        <RecipeFlow result={result} items={items} editing={editing} />
      ) : (
        <StepList result={result} items={items} editing={editing} />
      )}
    </Stack>
  )
}

const DEFAULT_PARAMS: EvaluateParams = {
  includeUnlearned: false,
  includeTrivial: true,
  exits: ['vendor', 'ah', 'disenchant'],
}

const NONE: ReadonlySet<number> = new Set()

const DOTS = (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
    <circle cx="3" cy="8" r="1.5" />
    <circle cx="8" cy="8" r="1.5" />
    <circle cx="13" cy="8" r="1.5" />
  </svg>
)

/** A row's ⋯ menu: stop or allow selling its output on the AH. */
function RowActions({
  result,
  blocked,
  onSetAhBlocked,
}: {
  result: RankResult
  blocked: boolean
  onSetAhBlocked: (itemId: number, blocked: boolean) => void
}) {
  return (
    <Menu position="bottom-end" withinPortal>
      <Menu.Target>
        <ActionIcon variant="subtle" color="gray" aria-label={`Actions for ${result.recipe}`}>
          {DOTS}
        </ActionIcon>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Item onClick={() => onSetAhBlocked(result.output_item_id, !blocked)}>
          {blocked ? 'Allow selling on auction house' : 'Never sell on auction house'}
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  )
}

export function ResultsTable({
  results,
  items: rankItems,
  classes: characterClasses = {},
  params = DEFAULT_PARAMS,
  ahBlocked = NONE,
  onSetAhBlocked,
}: {
  results: RankResult[]
  items: ItemMap
  /** Character name -> class file, for class-coloured names. */
  classes?: Readonly<Record<string, string>>
  /** The search the results came from: a recipe whose plan the user changes is re-costed the same way. */
  params?: EvaluateParams
  /** Item ids never sold on the AH. */
  ahBlocked?: ReadonlySet<number>
  /** Stop or allow selling an item on the AH; without it rows have no actions menu. */
  onSetAhBlocked?: (itemId: number, blocked: boolean) => void
}) {
  const columns = COLUMNS.length + (onSetAhBlocked ? 1 : 0)
  const [open, setOpen] = useState<ReadonlySet<number>>(new Set())
  const toggle = (id: number) =>
    setOpen((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  const [sort, setSort] = useState<Sort | null>(null)
  const sortBy = (column: string) =>
    setSort((prev) =>
      prev?.column === column
        ? { column, descending: !prev.descending }
        : { column, descending: NUMERIC_COLUMNS.has(column) },
    )
  // The user's changes to each recipe's plan, by recipe id; a row shows its changed plan once it is costed.
  const [choices, setChoices] = useState<Readonly<Record<number, Choices>>>({})
  const evaluations = useEvaluations(choices, params)
  const current = useMemo(
    () => results.map((r) => (choices[r.recipe_id] && evaluations[r.recipe_id]?.data?.result) || r),
    [results, choices, evaluations],
  )
  const items = useMemo(
    () => Object.assign({}, rankItems, ...Object.values(evaluations).map((e) => e.data?.items ?? {})) as ItemMap,
    [rankItems, evaluations],
  )
  const rows = useMemo(() => sorted(current, sort), [current, sort])
  const editing = (id: number): PlanEditing => {
    const evaluation = evaluations[id]
    return {
      onChoose: (paths, key) =>
        setChoices((prev) => ({ ...prev, [id]: paths.reduce((c, path) => choose(c, path, key), prev[id] ?? {}) })),
      modified: id in choices,
      onReset: () => setChoices((prev) => Object.fromEntries(Object.entries(prev).filter(([k]) => Number(k) !== id))),
      pending: evaluation?.isFetching ?? false,
      error: evaluation?.error?.message ?? null,
    }
  }

  return (
    <CharacterClasses.Provider value={characterClasses}>
      <Table.ScrollContainer minWidth={360}>
        <Table striped highlightOnHover stickyHeader>
          <Table.Thead>
            <Table.Tr>
              {COLUMNS.map((c) => {
                const active = sort?.column === c
                return (
                  <Table.Th
                    key={c}
                    className={COLUMN_HIDDEN[c]}
                    w={COLUMN_WIDTHS[c]}
                    ta={MONEY_COLUMNS.has(c) ? 'right' : undefined}
                    aria-sort={!(c in SORT_KEYS) ? undefined : !active ? 'none' : sort.descending ? 'descending' : 'ascending'}
                  >
                    {c in SORT_KEYS ? (
                      <UnstyledButton className={classes.sort} aria-label={`Sort by ${c}`} onClick={() => sortBy(c)}>
                        {c}
                        <span className={classes.arrow} data-active={active || undefined}>
                          {active && !sort.descending ? '▲' : '▼'}
                        </span>
                      </UnstyledButton>
                    ) : (
                      c
                    )}
                  </Table.Th>
                )
              })}
              {onSetAhBlocked && <Table.Th w={44} aria-label="Actions" />}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {rows.map((r) => {
              const expanded = open.has(r.recipe_id)
              const modified = r.recipe_id in choices
              return (
                <Fragment key={r.recipe_id}>
                  <Table.Tr onClick={() => toggle(r.recipe_id)} style={{ cursor: 'pointer' }}>
                    <Table.Td>
                      <UnstyledButton
                        aria-expanded={expanded}
                        aria-label={`Details for ${r.recipe}`}
                        onClick={(e) => {
                          e.stopPropagation()
                          toggle(r.recipe_id)
                        }}
                      >
                        {expanded ? '▾' : '▸'}
                      </UnstyledButton>
                      {modified && (
                        <Text span c="yellow" ml={4} title="Your changed plan, not the best one" aria-label="Changed plan">
                          ●
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td c={r.profit < 0 ? 'red' : 'teal'} ff="monospace" ta="right">
                      <Money copper={r.profit} padded />
                    </Table.Td>
                    <Table.Td>{formatRoi(r.roi)}</Table.Td>
                    <Table.Td>
                      <ItemLink
                        item={items[r.output_item_id]}
                        name={r.output_name}
                        tooltip={
                          <RecipeTooltip
                            name={r.recipe}
                            profession={r.profession}
                            reagents={r.reagents}
                            output={items[r.output_item_id]}
                            items={items}
                          />
                        }
                      />
                    </Table.Td>
                    <Table.Td className={COLUMN_HIDDEN.Profession}>{r.profession}</Table.Td>
                    <Table.Td
                      className={COLUMN_HIDDEN.Crafter}
                      title={r.crafters.length > 1 ? byCrafter(r.crafters, r.crafter).join(', ') : undefined}
                    >
                      {r.crafters.length ? (
                        <>
                          <CharacterName name={byCrafter(r.crafters, r.crafter)[0]} />
                          {r.crafters.length > 1 &&
                            ` (and ${r.crafters.length - 1} other${r.crafters.length > 2 ? 's' : ''})`}
                        </>
                      ) : (
                        <Text span size="sm" c="dimmed">
                          {/* no crafter named: browsing without characters */}
                          {r.crafter ? 'not learned' : 'anyone'}
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td className={COLUMN_HIDDEN.Cost} ff="monospace" ta="right">
                      <Money copper={r.cost} cost padded />
                    </Table.Td>
                    <Table.Td className={COLUMN_HIDDEN.Revenue} c="teal" ff="monospace" ta="right">
                      <Money copper={r.revenue} padded />
                    </Table.Td>
                    <Table.Td className={COLUMN_HIDDEN['Sell via']}>{exitLabel(r.best_exit)}</Table.Td>
                    {onSetAhBlocked && (
                      // Menu clicks (in its portal too) bubble here in React, not to the row.
                      <Table.Td onClick={(e) => e.stopPropagation()}>
                        <RowActions
                          result={r}
                          blocked={ahBlocked.has(r.output_item_id)}
                          onSetAhBlocked={onSetAhBlocked}
                        />
                      </Table.Td>
                    )}
                  </Table.Tr>
                  {expanded && (
                    <Table.Tr className={classes.details}>
                      <Table.Td />
                      <Table.Td colSpan={columns - 1}>
                        <Details result={r} items={items} editing={editing(r.recipe_id)} />
                      </Table.Td>
                    </Table.Tr>
                  )}
                </Fragment>
              )
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </CharacterClasses.Provider>
  )
}
