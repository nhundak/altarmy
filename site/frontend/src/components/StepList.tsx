import { Fragment, type ReactNode } from 'react'
import { List, Text } from '@mantine/core'
import type { ItemMap, RankResult, Step } from '../api/client'
import { useAhCut } from '../api/queries'
import { SELL_PATH } from '../lib/choices'
import { breakEven, countedOn, floor } from '../lib/selling'
import { stepSource } from '../lib/steps'
import { bonusNote, discountLabel } from '../lib/talents'
import { formatCoords } from '../lib/time'
import { CharacterName } from './CharacterName'
import { DiscountTooltip } from './DiscountTooltip'
import { ChoiceMenu, ChooseContext, sellChoices, sourceChoices, type PlanEditing } from './ChoiceMenu'
import { DisenchantHover, Hover, ItemLink } from './ItemTooltip'
import { Money } from './Money'
import classes from './ResultsTable.module.css'
import { ZoneMap } from './ZoneMap'

/** A step's amount: spending is a cost (red, unsigned), income is a signed gain. */
const StepMoney = ({ value }: { value: number }) =>
  value < 0 ? <Money copper={-value} cost /> : <Money copper={value} signed />

/** Money made, green or (a loss) red, without a sign unless `minus` marks a loss with one. */
export const Earned = ({ copper, minus = false }: { copper: number; minus?: boolean }) => (
  <Text span inherit c={copper < 0 ? 'red' : 'teal'}>
    <Money copper={minus ? copper : Math.abs(copper)} />
  </Text>
)

/** A sale's gross and the recipe's net profit. */
const Sale = ({ gross, net }: { gross: number; net: number }) => (
  <>
    (Gross <Earned copper={gross} /> · Net <Earned copper={net} />)
  </>
)

/** What to watch for when posting the craft: the price under which another exit pays more, the price under which
 * the session loses gold, and what the plan counted on. */
function SaleNotes({ result, items }: { result: RankResult; items: ItemMap }) {
  const cut = useAhCut()
  const lowest = floor(result, cut)
  const even = breakEven(result, cut)
  const counted = countedOn(result, items)
  return (
    <Text component="span" size="xs" c="dimmed" display="block">
      {lowest !== null && (
        <>
          Don&apos;t go under <Money copper={lowest} /> each: below that the {result.exits.find((e) => e.kind !== 'ah')?.kind === 'vendor' ? 'vendor' : 'other way to sell'} pays more.{' '}
        </>
      )}
      Under <Money copper={even} /> each this run loses gold (deposit not included).
      {counted.price !== null && (
        <>
          {' '}
          We counted on <Money copper={counted.price} /> for {counted.units} of your {counted.of}.
        </>
      )}
    </Text>
  )
}

/** Who does a line: their name and a colon, or nothing when no characters are known. */
const Who = ({ who }: { who: string }) =>
  who ? (
    <>
      <CharacterName name={who} />:{' '}
    </>
  ) : null

/**
 * A step as one or more instruction lines, prefixed with who does it; disenchanting splits into disenchant,
 * then sell the mats. `vendor` names the vendor bought from or sold to (the detailed view knows it).
 */
function describe(step: Step, result: RankResult, items: ItemMap, vendor?: string, skill = false): ReactNode[] {
  return describeAction(step, result, items, vendor, skill).map((l) => (
    <>
      <Who who={step.who} />
      {l}
    </>
  ))
}

function describeAction(
  { action, item_id, name, quantity, value, via, who, discount, rep_discount, rep_faction, bonus, convert, enchant }: Step,
  result: RankResult,
  items: ItemMap,
  vendor?: string,
  skill = false,
): ReactNode[] {
  const item = <ItemLink item={items[item_id]} name={name} />
  const discounted = discountLabel(discount, rep_discount)
  const extra = bonus > 0 ? ` (${bonusNote(bonus)})` : ''
  switch (action) {
    case 'buy':
      return [
        <>
          Purchase {quantity}x {item} {via === 'vendor' ? `from ${vendor ?? 'a vendor'}` : 'on the AH'} (
          <StepMoney value={value} />
          {discounted && (
            <>
              ,{' '}
              <Hover
                tooltip={
                  <DiscountTooltip who={who} discount={discount} repDiscount={rep_discount} repFaction={rep_faction} />
                }
              >
                <span className={classes.hint}>{discounted}</span>
              </Hover>
            </>
          )}
          )
        </>,
      ]
    case 'gather':
      // the user's own: what it costs is what selling it would have made
      return [
        <>
          Gather {quantity}x {item} (worth <Money copper={-value} /> to sell)
        </>,
      ]
    case 'craft':
      // an enchant makes no item: the step is the spell, cast on anything it can go on
      if (enchant) return [<>Cast {name} {quantity === 1 ? 'once' : `${quantity} times`}</>]
      return [
        <>
          {convert ? 'Convert into' : 'Craft'} {quantity}x {item}
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
            {extra} (
            <DisenchantHover result={result} items={items}>
              <span className={classes.hint}>view expected materials</span>
            </DisenchantHover>
            )
          </>,
          <>
            <DisenchantHover result={result} items={items}>
              Sell materials
            </DisenchantHover>{' '}
            <Sale gross={value} net={result.profit} />
          </>,
        ]
      if (via === 'keep')
        return [
          <>
            Keep the {quantity > 1 ? `${quantity}x ` : ''}
            {item}
            {extra} (no vendor buys it)
          </>,
        ]
      // skilling up sells what was made only to win some of the cost back: no notes on how to post it
      return [
        <>
          Sell {quantity}x {item}
          {extra} {via === 'ah' ? 'on the AH' : `to ${vendor ?? 'a vendor'}`} <Sale gross={value} net={result.profit} />
          {via === 'ah' && !skill && <SaleNotes result={result} items={items} />}
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

/** A step's lines (a disenchant sale's split: disenchanting, then selling the materials), the last ending in a
 * menu of its alternatives, if it has any. */
function stepLines(step: Step, result: RankResult, items: ItemMap, vendor?: string, skill = false): ReactNode[] {
  return describe(step, result, items, vendor, skill).map((line, i, all) =>
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
  )
}

type Detail = RankResult['details'][number]

/** "`verb` <place> at x, y", showing the zone map with the spot marked on hover when it is known. */
function Place({ verb, location }: { verb: string; location: NonNullable<Detail['location']> }) {
  const { name, map_x: x, map_y: y, map_area: area } = location
  const text = (
    <>
      {verb} {name}
      {x != null && y != null && ` at ${formatCoords(x, y)}`}
    </>
  )
  return area != null && x != null && y != null ? (
    <Hover tooltip={<ZoneMap area={area} x={x} y={y} name={name} />}>
      <span className={classes.mapLink}>{text}</span>
    </Hover>
  ) : (
    text
  )
}

/** Where a character's stretch starts. */
function startLine({ who, location }: Detail): ReactNode {
  if (!location) return null
  return (
    <>
      <Who who={who} />
      <Place verb="Start at" location={location} />
    </>
  )
}

/** A run to somewhere, with what to take from the mailbox there. */
function goLine({ who, location, retrieve }: Detail, items: ItemMap): ReactNode {
  if (!location) return null
  return (
    <>
      <Who who={who} />
      <Place verb="Run to" location={location} />
      .
      {retrieve.length > 0 && (
        <>
          {' '}
          Retrieve{' '}
          {retrieve.map(({ item_id, count }, i) => (
            <Fragment key={item_id}>
              {i > 0 && ', '}
              {count}x <ItemLink item={items[item_id]} name={items[item_id]?.name ?? `item ${item_id}`} />
            </Fragment>
          ))}
          .
        </>
      )}
    </>
  )
}

/** The plan's lines: its steps, or with `detailed` its steps with where to go in between. */
function planLines(result: RankResult, items: ItemMap, detailed: boolean): ReactNode[] {
  if (!detailed || result.details.length === 0) return result.steps.flatMap((step) => stepLines(step, result, items))
  let vendor: string | undefined // the vendor the character stands at, to name in buy and sell lines
  return result.details.flatMap((d): ReactNode[] => {
    if (d.kind === 'switch') {
      vendor = undefined
      return [
        <>
          Switch to <CharacterName name={d.who} />
        </>,
      ]
    }
    if (d.kind === 'start') {
      vendor = d.location?.kind === 'vendor' ? d.location.name : undefined
      return [startLine(d)]
    }
    if (d.kind === 'go') {
      vendor = d.location?.kind === 'vendor' ? d.location.name : undefined
      return [goLine(d, items)]
    }
    const step = d.step == null ? undefined : result.steps[d.step]
    return step ? stepLines(step, result, items, vendor) : []
  })
}

/**
 * The plan as numbered instructions; with `editing`, a step with alternatives ends in a menu of them. In `skill` mode
 * (skilling up: a checklist) the steps are grouped under each character in the order they do them, and an AH sale
 * has no posting notes; `learn`, a step learning the recipe, comes first among the final crafter's.
 */
export function StepList({
  result,
  items,
  editing,
  detailed = false,
  mode = 'default',
  learn,
}: {
  result: RankResult
  items: ItemMap
  editing?: PlanEditing
  detailed?: boolean
  mode?: 'default' | 'skill'
  learn?: ReactNode
}) {
  if (mode === 'skill') {
    const groups: { who: string; steps: Step[]; learn?: ReactNode }[] = []
    for (const step of result.steps) {
      const last = groups.at(-1)
      if (last && last.who === step.who) last.steps.push(step)
      else groups.push({ who: step.who, steps: [step] })
    }
    if (learn) {
      const crafter = groups.find((g) => g.who === result.crafter)
      if (crafter) crafter.learn = learn
      else groups.unshift({ who: result.crafter, steps: [], learn })
    }
    return (
      <ChooseContext.Provider value={editing?.onChoose}>
        {groups.map((g, n) => (
          <div key={n} role="group" aria-label={g.who ? `${g.who}'s steps` : 'Steps'}>
            {g.who && (
              <Text size="sm" fw={600} mt={n ? 'xs' : 0}>
                <CharacterName name={g.who} />
              </Text>
            )}
            <List type="ordered" size="sm">
              {g.learn && <List.Item>{g.learn}</List.Item>}
              {g.steps.flatMap((step, i) =>
                describeAction(step, result, items, undefined, true).map((line, j, all) => (
                  <List.Item key={`${i}.${j}`}>
                    {line}
                    {j === all.length - 1 && (
                      <span className={classes.stepChoice}>
                        <StepChoice step={step} result={result} />
                      </span>
                    )}
                  </List.Item>
                )),
              )}
            </List>
          </div>
        ))}
      </ChooseContext.Provider>
    )
  }
  const lines = planLines(result, items, detailed)
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
