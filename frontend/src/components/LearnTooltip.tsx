import { Stack, Text, Tooltip } from '@mantine/core'
import type { Learn } from '../api/client'

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

/** Where to learn a recipe: its trainer, or each item teaching it and where that comes from. */
export function LearnDetails({ learn }: { learn: Learn }) {
  const skill = learn.skill ? ` ${learn.skill}` : ''
  if (learn.source === 'trainer' || !learn.items.length) {
    return <Text size="sm">{`Taught by ${learn.profession || 'profession'} trainers${skill ? ` (skill${skill})` : ''}`}</Text>
  }
  const placed = learn.items.some((i) => i.places.length)
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
      {placed && (
        <Text size="xs" c="dimmed">
          From vanilla's world data; WoW: Forever may differ
        </Text>
      )}
    </Stack>
  )
}

/** `children` (the results table's "not learned") explained on hover, focus or tap: where to learn the recipe. */
export function LearnTooltip({ learn, children }: { learn: Learn; children: string }) {
  return (
    <Tooltip
      label={<LearnDetails learn={learn} />}
      multiline
      maw={340}
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
