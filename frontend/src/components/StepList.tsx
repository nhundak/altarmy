import { Fragment, type ReactNode } from 'react'
import { List, Text } from '@mantine/core'
import type { ItemMap, RankResult, Step } from '../api/client'
import { SELL_PATH } from '../lib/choices'
import { stepSource } from '../lib/steps'
import { bonusNote, discountNote } from '../lib/talents'
import { formatCoords, formatSeconds } from '../lib/time'
import { CharacterName } from './CharacterName'
import { ChoiceMenu, ChooseContext, sellChoices, sourceChoices, type PlanEditing } from './ChoiceMenu'
import { DisenchantHover, Hover, ItemLink } from './ItemTooltip'
import { Money } from './Money'
import classes from './ResultsTable.module.css'
import { ZoneMap } from './ZoneMap'

/** A step's amount: spending is a cost (red, unsigned), income is a signed gain. */
const StepMoney = ({ value }: { value: number }) =>
  value < 0 ? <Money copper={-value} cost /> : <Money copper={value} signed />

/** Money made, green or (a loss) red, without a sign. */
export const Earned = ({ copper }: { copper: number }) => (
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
function describe(step: Step, result: RankResult, items: ItemMap, vendor?: string): ReactNode[] {
  return describeAction(step, result, items, vendor).map((l) => (
    <>
      <Who who={step.who} />
      {l}
    </>
  ))
}

function describeAction(
  { action, item_id, name, quantity, value, via, discount, rep_discount, rep_faction, bonus }: Step,
  result: RankResult,
  items: ItemMap,
  vendor?: string,
): ReactNode[] {
  const item = <ItemLink item={items[item_id]} name={name} />
  const discounted = discountNote(discount, rep_discount, rep_faction)
  const extra = bonus > 0 ? ` (${bonusNote(bonus)})` : ''
  switch (action) {
    case 'buy':
      return [
        <>
          Purchase {quantity}x {item} {via === 'vendor' ? `from ${vendor ?? 'a vendor'}` : 'on the AH'} (
          <StepMoney value={value} />
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
          {extra} {via === 'ah' ? 'on the AH' : `to ${vendor ?? 'a vendor'}`} <Sale gross={value} net={result.profit} />
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

/** A step's lines, the last ending in its time and, where there is a choice, a menu of it. */
/** A dimmed " · 12 s" after a line; nothing for no time. */
const Took = ({ seconds }: { seconds: number }) =>
  seconds >= 0.05 ? (
    <Text span size="xs" c="dimmed">
      {' '}
      · {formatSeconds(seconds)}
    </Text>
  ) : null

/** A step's lines, each ending in its time (a disenchant sale's split: disenchanting, then selling the
 * materials); the last also in a menu of its alternatives, if it has any. */
function stepLines(step: Step, result: RankResult, items: ItemMap, vendor?: string): ReactNode[] {
  return describe(step, result, items, vendor).map((line, i, all) =>
    i < all.length - 1 ? (
      <>
        {line}
        <Took seconds={step.lead_seconds} />
      </>
    ) : (
      <>
        {line}
        <Took seconds={all.length > 1 ? step.seconds - step.lead_seconds : step.seconds} />
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

/** Where a character's stretch starts; standing there takes no time, so no time is shown. */
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
function goLine({ who, location, retrieve, seconds }: Detail, items: ItemMap): ReactNode {
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
      <Took seconds={seconds} />
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
          <Took seconds={d.seconds} />
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

/** The plan as numbered instructions; with `editing`, a step with alternatives ends in a menu of them. */
export function StepList({
  result,
  items,
  editing,
  detailed = false,
}: {
  result: RankResult
  items: ItemMap
  editing?: PlanEditing
  detailed?: boolean
}) {
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
