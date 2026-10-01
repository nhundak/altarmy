import { Fragment, useMemo, useState } from 'react'
import { ActionIcon, Menu, Table, Text, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion } from 'motion/react'
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

/** Profit after costs, AH cut and postage. */
const PROFIT = 'Net profit'
/** Profit per skill point the crafter can expect: the rate column when skilling up. */
const PER_SKILL = 'Per skill up'
/** Profit per hour of play: the rate column when making gold. */
const PER_HOUR = 'Per hour'
/** The columns in order; the second shows the rate the goal cares about. */
const columnsFor = (rankBy: RankBy | undefined): string[] => [
  '',
  PROFIT,
  rankBy === 'skill' ? PER_SKILL : PER_HOUR,
  'Investment',
  'ROI',
  'Recipe',
  'Crafter',
  'Sell via',
]
/** Profit per expected skill point (negative: what one costs); null when the craft can't give one. */
const perSkillUp = (r: RankResult): number | null => (r.skill_ups ? r.profit / r.skill_ups : null)
/** Sell via column text per exit; unknown exits show as-is. */
const EXIT_LABELS: Readonly<Record<string, string>> = { ah: 'Auction', vendor: 'Vendor', disenchant: 'Disenchant' }
/** The Recipe tooltip's profession line for what needs no profession. */
const KIND_NOTES: Readonly<Record<string, string>> = {
  convert: 'Essence conversion (use the item; no profession)',
  flip: 'Buy and disenchant (no crafting)',
}
const exitLabel = (exit: string): string => EXIT_LABELS[exit] ?? exit.charAt(0).toUpperCase() + exit.slice(1)
/** Sort key per sortable column; numbers sort largest first on the first click, text alphabetically. */
const SORT_KEYS: Readonly<Record<string, (r: RankResult) => number | string>> = {
  [PROFIT]: (r) => r.profit,
  [PER_HOUR]: (r) => r.timing?.per_hour ?? -Infinity,
  [PER_SKILL]: (r) => perSkillUp(r) ?? -Infinity,
  ROI: (r) => r.roi,
  Recipe: (r) => r.output_name,
  Crafter: (r) => (r.crafters.length ? r.crafter : ''),
  Investment: (r) => r.cost,
  'Sell via': (r) => exitLabel(r.best_exit),
}
const NUMERIC_COLUMNS: ReadonlySet<string> = new Set(['Investment', PROFIT, PER_HOUR, PER_SKILL, 'ROI'])
/** Money columns: fixed width, room for -99g 99s 99c on one line (larger amounts drop copper, then silver). */
const MONEY_COLUMNS: ReadonlySet<string> = new Set(['Investment', PROFIT, PER_HOUR, PER_SKILL])
const MONEY_WIDTH = 110
/** Crafter lists wrap at this width (px). */
const CRAFTER_WIDTH = 219
/** Columns dropped as the screen narrows (ResultsTable.module.css): Investment and Crafter first, then Sell via
 * and the rate. */
const COLUMN_HIDDEN: Readonly<Record<string, string | undefined>> = {
  Investment: classes.hideBelowSm,
  Crafter: classes.hideBelowSm,
  'Sell via': classes.hideBelowXs,
  [PER_HOUR]: classes.hideBelowXs,
  [PER_SKILL]: classes.hideBelowXs,
}
/** What the server can rank by (the whole ranking, not just this page): profit per session, per hour, or per
 * expected skill point. */
export type RankBy = 'profit' | 'rate' | 'skill'
/** The column showing each ranking. */
const RANK_COLUMN: Readonly<Record<RankBy, string>> = { profit: PROFIT, rate: PER_HOUR, skill: PER_SKILL }

type Sort = { column: string; descending: boolean }

/** Rows slide to their new place when the order changes (a favorite, a re-rank, a sort). */
const MotionTr = motion.create(Table.Tr)
const REORDER = { layout: { duration: 0.35, ease: [0.25, 0.8, 0.25, 1] as const } }
/** A details row opens and closes by its content's height (a table row's own height can't be animated), so
 * its cells have no padding of their own. */
const UNFOLD = {
  initial: { height: 0, opacity: 0 },
  animate: { height: 'auto', opacity: 1 },
  exit: { height: 0, opacity: 0 },
  transition: { duration: 0.25, ease: [0.25, 0.8, 0.25, 1] as const },
  style: { overflow: 'hidden' },
}

/** `results` ordered by `sort`, stably, favorites first; unsorted keeps the server's order (favorites, then
 * profit, best first). */
function sorted(results: RankResult[], sort: Sort | null, favorites: ReadonlySet<number>): RankResult[] {
  const key = sort && SORT_KEYS[sort.column]
  const sign = sort?.descending ? -1 : 1
  return results.toSorted((a, b) => {
    const f = Number(favorites.has(b.recipe_id)) - Number(favorites.has(a.recipe_id))
    if (f || !key) return f
    const x = key(a)
    const y = key(b)
    const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))
    return sign * c
  })
}

/** A row's profit per hour of play, with the session's time on hover. */
function PerHourCell({ result: r }: { result: RankResult }) {
  return (
    <Table.Td
      className={COLUMN_HIDDEN[PER_HOUR]}
      ff="monospace"
      ta="right"
      title={
        r.timing ? `${r.crafts} ${r.crafts === 1 ? 'craft' : 'crafts'} in ${formatSeconds(r.timing.total_seconds)}` : undefined
      }
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
  )
}

/** A row's profit per expected skill point, with the chance of one on hover. */
function PerSkillCell({ result: r }: { result: RankResult }) {
  const value = perSkillUp(r)
  const crafts = `${r.crafts} ${r.crafts === 1 ? 'craft' : 'crafts'}`
  return (
    <Table.Td
      className={COLUMN_HIDDEN[PER_SKILL]}
      ff="monospace"
      ta="right"
      title={`${Math.round(r.skill_chance * 100)}% chance of a skill point on the first craft ·${r.skill_ups.toFixed(1)} expected from ${crafts}`}
    >
      {value === null ? (
        <Text span size="sm" c="dimmed">
          –
        </Text>
      ) : (
        <Text span inherit c={value < 0 ? 'red' : 'teal'}>
          <Money copper={Math.round(value)} padded />
        </Text>
      )}
    </Table.Td>
  )
}

/** The characters who know the recipe, the one doing the craft first. */
const byCrafter = (crafters: string[], crafter: string) =>
  crafters.includes(crafter) ? [crafter, ...crafters.filter((c) => c !== crafter)] : crafters

const DEFAULT_PARAMS: EvaluateParams = {
  unlearned: 'none',
  includeTrivial: true,
  skillCrafters: [],
  exits: ['vendor', 'ah', 'disenchant'],
  arcaneSalvager: false,
}

const NONE: ReadonlySet<number> = new Set()

const DOTS = (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
    <circle cx="3" cy="8" r="1.5" />
    <circle cx="8" cy="8" r="1.5" />
    <circle cx="13" cy="8" r="1.5" />
  </svg>
)

/** Why a row's sale is flagged: how long it may take, or else how few units its price rests on. */
function slowTitle(result: RankResult, output: ItemMap[string] | undefined): string {
  if (result.days_to_sell != null) {
    const days = Math.round(result.days_to_sell)
    return `May take about ${days} ${days === 1 ? 'day' : 'days'} to sell at the rate it sold lately`
  }
  const listed = output?.ah_quantity
  if (listed == null) return 'Sell price rests on few listed units'
  return `Sell price rests on ${listed} listed ${listed === 1 ? 'unit' : 'units'}`
}

/** Why a row is flagged as buying more than the auction house lists. */
function shortTitle(short: number): string {
  return `Needs ${short.toLocaleString()} more ${short === 1 ? 'unit' : 'units'} than the auction house lists; they are counted at the dearest price listed`
}

/** A row's ⋯ menu: mark the recipe as a favorite or not, stop or allow selling its output on the AH. */
function RowActions({
  result,
  blocked,
  onSetAhBlocked,
  favorite,
  onSetFavorite,
}: {
  result: RankResult
  blocked: boolean
  onSetAhBlocked?: (itemId: number, blocked: boolean) => void
  favorite: boolean
  onSetFavorite?: (recipeId: number, favorite: boolean) => void
}) {
  return (
    <Menu position="bottom-end" withinPortal>
      <Menu.Target>
        <ActionIcon variant="subtle" color="gray" aria-label={`Actions for ${result.recipe}`}>
          {DOTS}
        </ActionIcon>
      </Menu.Target>
      <Menu.Dropdown>
        {onSetFavorite && (
          <Menu.Item onClick={() => onSetFavorite(result.recipe_id, !favorite)}>
            {favorite ? 'Remove from favorites' : 'Add to favorites'}
          </Menu.Item>
        )}
        {onSetAhBlocked && (
          <Menu.Item onClick={() => onSetAhBlocked(result.output_item_id, !blocked)}>
            {blocked ? 'Allow selling on auction house' : 'Never sell on auction house'}
          </Menu.Item>
        )}
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
  favorites = NONE,
  onSetFavorite,
  rankBy,
}: {
  results: RankResult[]
  items: ItemMap
  /** Character name -> class file, for class-coloured names. */
  classes?: Readonly<Record<string, string>>
  /** The search the results came from: a recipe whose plan the user changes is re-costed the same way. */
  params?: EvaluateParams
  /** Item ids never sold on the AH. */
  ahBlocked?: ReadonlySet<number>
  /** Stop or allow selling an item on the AH; without it and `onSetFavorite` rows have no actions menu. */
  onSetAhBlocked?: (itemId: number, blocked: boolean) => void
  /** Favorite recipe ids: listed first and highlighted. */
  favorites?: ReadonlySet<number>
  /** Mark a recipe as a favorite or not. */
  onSetFavorite?: (recipeId: number, favorite: boolean) => void
  /** What the server ranked `results` by (best first): its column shows as sorted until the user sorts the page
   * by a header (which orders only the rows loaded, like every other column). */
  rankBy?: RankBy
}) {
  const actions = Boolean(onSetAhBlocked || onSetFavorite)
  const shownColumns = columnsFor(rankBy)
  const columns = shownColumns.length + (actions ? 1 : 0)
  const [open, setOpen] = useState<ReadonlySet<number>>(new Set())
  const toggle = (id: number) =>
    setOpen((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  const [sort, setSort] = useState<Sort | null>(null)
  // With no column picked here, the server's order shows on the column it ranked by.
  const shownSort: Sort | null =
    sort ?? (rankBy ? { column: RANK_COLUMN[rankBy], descending: true } : null)
  const sortBy = (column: string) =>
    setSort(
      shownSort?.column === column
        ? { column, descending: !shownSort.descending }
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
  const rows = useMemo(() => sorted(current, sort, favorites), [current, sort, favorites])
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
              {shownColumns.map((c) => {
                const active = shownSort?.column === c
                return (
                  <Table.Th
                    key={c}
                    className={COLUMN_HIDDEN[c]}
                    w={MONEY_COLUMNS.has(c) ? MONEY_WIDTH : c === 'Crafter' ? CRAFTER_WIDTH : undefined}
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
              {actions && <Table.Th w={44} aria-label="Actions" />}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {rows.map((r, index) => {
              const expanded = open.has(r.recipe_id)
              const modified = r.recipe_id in choices
              const favorite = favorites.has(r.recipe_id)
              // Measured only when the row's place in the order changes, so expanding a row above doesn't
              // slide the rows below it.
              const reorder = { layout: 'position', layoutDependency: index, transition: REORDER } as const
              return (
                <Fragment key={r.recipe_id}>
                  <MotionTr
                    {...reorder}
                    onClick={() => toggle(r.recipe_id)}
                    style={{ cursor: 'pointer' }}
                    className={favorite ? classes.favorite : undefined}
                  >
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
                      {favorite && (
                        <Text span c="yellow" ml={4} title="Favorite" aria-label="Favorite">
                          ★
                        </Text>
                      )}
                      {r.slow && (
                        <Text span c="orange" ml={4} title={slowTitle(r, items[r.output_item_id])} aria-label="Slow to sell">
                          ⚠
                        </Text>
                      )}
                      {r.short > 0 && (
                        <Text span c="orange" ml={4} title={shortTitle(r.short)} aria-label="Not enough listed">
                          ◔
                        </Text>
                      )}
                      {modified && (
                        <Text span c="yellow" ml={4} title="Your changed plan, not the best one" aria-label="Changed plan">
                          ●
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td c={r.profit < 0 ? 'red' : 'teal'} ff="monospace" ta="right">
                      <Money copper={r.profit} padded />
                    </Table.Td>
                    {rankBy === 'skill' ? <PerSkillCell result={r} /> : <PerHourCell result={r} />}
                    <Table.Td className={COLUMN_HIDDEN.Investment} ff="monospace" ta="right">
                      <Money copper={r.cost} cost padded />
                    </Table.Td>
                    <Table.Td c={r.roi < 0 ? 'red' : undefined}>{formatRoi(r.roi)}</Table.Td>
                    <Table.Td>
                      <ItemLink
                        item={items[r.output_item_id]}
                        name={r.output_name}
                        tooltip={
                          <RecipeTooltip
                            name={r.recipe}
                            profession={KIND_NOTES[r.kind] ?? r.profession}
                            reagents={r.reagents}
                            output={items[r.output_item_id]}
                            items={items}
                          />
                        }
                      />
                    </Table.Td>
                    <Table.Td
                      className={COLUMN_HIDDEN.Crafter}
                      title={r.crafters.length > 1 ? byCrafter(r.crafters, r.crafter).join(', ') : undefined}
                    >
                      {r.kind !== 'craft' && r.crafter ? (
                        // a conversion or flip needs no recipe: whoever the plan picks does it
                        <CharacterName name={r.crafter} />
                      ) : r.crafters.length ? (
                        <>
                          <CharacterName name={byCrafter(r.crafters, r.crafter)[0]} />
                          {r.crafters.length > 1 &&
                            ` (and ${r.crafters.length - 1} other${r.crafters.length > 2 ? 's' : ''})`}
                        </>
                      ) : (
                        <Text span size="sm" c="dimmed">
                          {/* no crafter named: browsing without characters */}
                          {r.crafter && r.kind === 'craft' ? 'not learned' : 'anyone'}
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td className={COLUMN_HIDDEN['Sell via']}>{exitLabel(r.best_exit)}</Table.Td>
                    {actions && (
                      // Menu clicks (in its portal too) bubble here in React, not to the row.
                      <Table.Td onClick={(e) => e.stopPropagation()}>
                        <RowActions
                          result={r}
                          blocked={ahBlocked.has(r.output_item_id)}
                          onSetAhBlocked={onSetAhBlocked}
                          favorite={favorite}
                          onSetFavorite={onSetFavorite}
                        />
                      </Table.Td>
                    )}
                  </MotionTr>
                  <AnimatePresence initial={false}>
                    {expanded && (
                      <MotionTr key="details" {...reorder} className={classes.details}>
                        <Table.Td py={0} />
                        <Table.Td py={0} colSpan={columns - 1}>
                          <motion.div {...UNFOLD}>
                            <SessionDetails
                              result={r}
                              items={items}
                              editing={editing(r.recipe_id)}
                              params={params}
                              choices={choices[r.recipe_id]}
                            />
                          </motion.div>
                        </Table.Td>
                      </MotionTr>
                    )}
                  </AnimatePresence>
                </Fragment>
              )
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </CharacterClasses.Provider>
  )
}
