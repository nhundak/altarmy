import { Stack, Text, Tooltip } from '@mantine/core'
import type { ItemMap, Learn } from '../api/client'
import { formatCoords } from '../lib/time'
import { Hover, ItemLink } from './ItemTooltip'
import { Money } from './Money'
import classes from './ResultsTable.module.css'
import { ZoneMap } from './ZoneMap'

type Place = Learn['items'][number]['places'][number]

/** A drop chance in percent, to two significant figures (0.012%, 1.9%, 35%). */
export function formatChance(percent: number): string {
  return `${Number(percent.toPrecision(2))}%`
}

const at = (zone: string): string => (zone ? `, ${zone}` : '')

/** One place a recipe item comes from, as a line. */
export function placeLine(p: Place): string {
  switch (p.kind) {
    case 'vendor':
      return `Sold by ${p.name}${at(p.zone)}${p.limited ? ' (limited stock)' : ''}`
    case 'quest':
      return `Quest: ${p.name}${at(p.zone)}${p.levels ? ` (level ${p.levels})` : ''}`
    case 'drop':
      return `Drops from ${p.name}${at(p.zone)} (${formatChance(p.chance)})`
    case 'object':
      return `Found in ${p.name}${at(p.zone)} (${formatChance(p.chance)})`
    case 'container':
      return `Found in ${p.name} (${formatChance(p.chance)})`
    case 'world_drop':
      return `World drop from ${p.count.toLocaleString()} creatures${p.levels ? `, levels ${p.levels.replace('-', '–')}` : ''}`
    case 'more':
      return `and ${p.count.toLocaleString()} more`
  }
}

/** What a recipe item without known places can still tell. */
function unplaced(source: Learn['source']): string {
  return source === 'bop' ? 'Bind on pickup: looted or earned in the world' : 'Tradable: look on the auction house'
}

/** The one vendor selling a recipe's items, if there is exactly one (whichever item it sells); none otherwise. */
export function onlyVendor(learn: Learn): Place | undefined {
  const vendors = new Map<string, Place>()
  for (const item of learn.items)
    for (const p of item.places) if (p.kind === 'vendor') vendors.set(`${p.name}|${p.zone}`, p)
  return vendors.size === 1 ? [...vendors.values()][0] : undefined
}

/** Where to learn a recipe: its trainer, or each item teaching it and where that comes from, with the map when
 * one vendor sells it. */
export function LearnDetails({ learn }: { learn: Learn }) {
  const skill = learn.skill ? ` ${learn.skill}` : ''
  if (learn.source === 'trainer' || !learn.items.length) {
    return <Text size="sm">{`Taught by ${learn.profession || 'profession'} trainers${skill ? ` (skill${skill})` : ''}`}</Text>
  }
  const placed = learn.items.some((i) => i.places.length)
  const vendor = onlyVendor(learn)
  return (
    <Stack gap={6}>
      {learn.items.map((item) => (
        <div key={item.item_id}>
          <Text size="sm" fw={600}>
            {item.name}
            {learn.profession && ` (${learn.profession}${skill})`}
          </Text>
          {item.places.length ? (
            item.places.map((p, i) => (
              <Text size="sm" key={i}>
                {placeLine(p)}
              </Text>
            ))
          ) : (
            <Text size="sm">{unplaced(learn.source)}</Text>
          )}
        </div>
      ))}
      {vendor && vendor.area > 0 && <ZoneMap area={vendor.area} x={vendor.map_x} y={vendor.map_y} name={vendor.name} />}
      {placed && (
        <Text size="xs" c="dimmed">
          From vanilla's world data; WoW: Forever may differ
        </Text>
      )}
    </Stack>
  )
}

/**
 * A skill-up checklist's first step when the climber lacks the recipe: the trainer, else buying the pattern that
 * costs `cost` (the cheapest of its items) from the vendor selling it (its zone map on hover) or on the AH, else
 * finding it. A pattern sold by a vendor is taken to be bought there.
 */
export function LearnStep({
  learn,
  recipe,
  cost,
  items,
}: {
  learn: Learn
  recipe: string
  cost: number | null
  items: ItemMap
}) {
  if (learn.source === 'trainer' || !learn.items.length)
    return <>Learn {recipe} from a {learn.profession || 'profession'} trainer</>
  const pattern = learn.items.find((i) => cost !== null && i.price === cost) ?? learn.items[0]!
  const link = <ItemLink item={items[pattern.item_id]} name={pattern.name} />
  if (cost === null)
    return (
      <>
        Find {link} (price unknown, <LearnTooltip learn={learn}>where to get it</LearnTooltip>)
      </>
    )
  const vendors = pattern.places.filter((p) => p.kind === 'vendor')
  const vendor = vendors[0]
  const price = (
    <>
      (<Money copper={cost} />)
    </>
  )
  if (!vendor)
    return (
      <>
        Buy {link} on the AH {price}
      </>
    )
  const where = (
    <>
      {vendor.name}
      {vendor.zone && `, ${vendor.zone}`}
      {vendor.area > 0 && ` at ${formatCoords(vendor.map_x, vendor.map_y)}`}
    </>
  )
  return (
    <>
      Buy {link} from{' '}
      {vendor.area > 0 ? (
        <Hover tooltip={<ZoneMap area={vendor.area} x={vendor.map_x} y={vendor.map_y} name={vendor.name} />}>
          <span className={classes.mapLink}>{where}</span>
        </Hover>
      ) : (
        where
      )}{' '}
      {price}
      {vendors.length > 1 && (
        <>
          {' '}
          or <LearnTooltip learn={learn}>{`${vendors.length - 1} other vendor${vendors.length > 2 ? 's' : ''}`}</LearnTooltip>
        </>
      )}
    </>
  )
}

/** `children` (the results table's "not learned") explained on hover, focus or tap: where to learn the recipe. */
export function LearnTooltip({ learn, children }: { learn: Learn; children: string }) {
  return (
    <Tooltip
      label={<LearnDetails learn={learn} />}
      multiline
      maw={onlyVendor(learn)?.area ? 460 : 340}
      withArrow
      openDelay={0}
      transitionProps={{ duration: 0 }}
      events={{ hover: true, focus: true, touch: true }}
    >
      <Text
        span
        size="sm"
        c="dimmed"
        tabIndex={0}
        style={{ cursor: 'help', textDecoration: 'underline dotted' }}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </Text>
    </Tooltip>
  )
}
