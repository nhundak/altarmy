import { Fragment, useMemo, useState } from 'react'
import { ActionIcon, Menu, Table, Text, UnstyledButton } from '@mantine/core'
import type { ItemMap, RankResult } from '../api/client'
import { useEvaluations, type EvaluateParams } from '../api/queries'
import { choose, type Choices } from '../lib/choices'
import { formatRoi } from '../lib/money'
import { formatSeconds } from '../lib/time'
import { CharacterClasses, CharacterName } from './CharacterName'
import { type PlanEditing } from './ChoiceMenu'
import { ItemLink, RecipeTooltip } from './ItemTooltip'
import { Money } from './Money'
import { SessionDetails } from './SessionDetails'
import classes from './ResultsTable.module.css'

const COLUMNS = ['', 'Profit', 'Per hour', 'ROI', 'Recipe', 'Profession', 'Crafter', 'Cost', 'Revenue', 'Sell via']
/** Sell via column text per exit; unknown exits show as-is. */
const EXIT_LABELS: Readonly<Record<string, string>> = { ah: 'auction' }
const exitLabel = (exit: string): string => EXIT_LABELS[exit] ?? exit
/** Sort key per sortable column; numbers sort largest first on the first click, text alphabetically. */
const SORT_KEYS: Readonly<Record<string, (r: RankResult) => number | string>> = {
  Profit: (r) => r.profit,
  'Per hour': (r) => r.timing?.per_hour ?? -Infinity,
  ROI: (r) => r.roi,
  Recipe: (r) => r.output_name,
  Profession: (r) => r.profession,
  Crafter: (r) => (r.crafters.length ? r.crafter : ''),
  Cost: (r) => r.cost,
  Revenue: (r) => r.revenue,
  'Sell via': (r) => exitLabel(r.best_exit),
}
const NUMERIC_COLUMNS: ReadonlySet<string> = new Set(['Profit', 'Per hour', 'ROI', 'Cost', 'Revenue'])
/** Money columns: fixed width, room for -99g 99s 99c on one line (larger amounts drop copper, then silver). */
const MONEY_COLUMNS: ReadonlySet<string> = new Set(['Profit', 'Per hour', 'Cost', 'Revenue'])
const MONEY_WIDTH = 110
/** Widths (px) for columns that should not just fit their content: crafter lists wrap, money never does. */
const COLUMN_WIDTHS: Readonly<Record<string, number>> = {
  Crafter: 219,
  Profit: MONEY_WIDTH,
  'Per hour': MONEY_WIDTH,
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
  'Per hour': classes.hideBelowXs,
}
/** The columns whose order the server can rank by (the whole ranking, not just this page). */
export type RankBy = 'profit' | 'rate'
const SERVER_SORTS: Readonly<Record<string, RankBy>> = { Profit: 'profit', 'Per hour': 'rate' }

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

/** The characters who know the recipe, the one doing the craft first. */
const byCrafter = (crafters: string[], crafter: string) =>
  crafters.includes(crafter) ? [crafter, ...crafters.filter((c) => c !== crafter)] : crafters

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
  rankBy,
  onRankBy,
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
  /** What the server ranked `results` by (best first). */
  rankBy?: RankBy
  /** Re-rank on the server: the Profit and Per hour headers call it instead of sorting this page. */
  onRankBy?: (rankBy: RankBy) => void
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
  const sortBy = (column: string) => {
    const server = SERVER_SORTS[column]
    if (onRankBy && server) {
      setSort(null)
      onRankBy(server)
      return
    }
    setSort((prev) =>
      prev?.column === column
        ? { column, descending: !prev.descending }
        : { column, descending: NUMERIC_COLUMNS.has(column) },
    )
  }
  // With no column picked here, the server's order shows on the column it ranked by.
  const shownSort: Sort | null =
    sort ?? (onRankBy && rankBy ? { column: rankBy === 'rate' ? 'Per hour' : 'Profit', descending: true } : null)
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
                const active = shownSort?.column === c
                return (
                  <Table.Th
                    key={c}
                    className={COLUMN_HIDDEN[c]}
                    w={COLUMN_WIDTHS[c]}
                    ta={MONEY_COLUMNS.has(c) ? 'right' : undefined}
                    aria-sort={
                      !(c in SORT_KEYS) ? undefined : !active ? 'none' : shownSort.descending ? 'descending' : 'ascending'
                    }
                  >
                    {c in SORT_KEYS ? (
                      <UnstyledButton className={classes.sort} aria-label={`Sort by ${c}`} onClick={() => sortBy(c)}>
                        {c}
                        <span className={classes.arrow} data-active={active || undefined}>
                          {active && !shownSort.descending ? '▲' : '▼'}
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
                    <Table.Td
                      className={COLUMN_HIDDEN['Per hour']}
                      ff="monospace"
                      ta="right"
                      title={r.timing ? `${r.timing.batch} crafts in ${formatSeconds(r.timing.total_seconds)}` : undefined}
                    >
                      {r.timing ? (
                        <Text span inherit c={r.timing.per_hour < 0 ? 'red' : 'teal'}>
                          <Money copper={r.timing.per_hour} padded />
                        </Text>
                      ) : (
                        <Text span size="sm" c="dimmed">
                          –
                        </Text>
                      )}
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
                        <SessionDetails
                          result={r}
                          items={items}
                          editing={editing(r.recipe_id)}
                          params={params}
                          choices={choices[r.recipe_id]}
                        />
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
