import { Fragment } from 'react'
import { List, Stack, Text } from '@mantine/core'
import type { ItemMap, RankResult } from '../api/client'
import { breakdownParts, formatSeconds } from '../lib/time'
import { CharacterName } from './CharacterName'
import { Money } from './Money'

type Leg = NonNullable<RankResult['timing']>['legs'][number]

/** Consecutive legs run by the same character, as one route. */
function routes(legs: readonly Leg[]): { who: string; legs: Leg[] }[] {
  const out: { who: string; legs: Leg[] }[] = []
  for (const leg of legs) {
    const last = out.at(-1)
    if (last && last.who === leg.who && last.legs.at(-1)?.to_id === leg.from_id) last.legs.push(leg)
    else out.push({ who: leg.who, legs: [leg] })
  }
  return out
}

/** Station kinds as words: cooking_fire reads "cooking fire". */
const stations = (kinds: readonly string[], joiner = ' or ') => kinds.map((k) => k.replaceAll('_', ' ')).join(joiner)

/** Copper per hour, coloured by its sign. */
const PerHour = ({ copper }: { copper: number }) => (
  <Text span inherit c={copper < 0 ? 'red' : 'teal'}>
    <Money copper={copper} />
    /hr
  </Text>
)

/** How long a batch of the recipe takes, where the characters run, and how the other cities compare. */
export function TimingSummary({ result, items }: { result: RankResult; items: ItemMap }) {
  const t = result.timing
  if (!t) return null
  const others = result.cities.length > 1 ? result.cities : []
  return (
    <Stack gap={4} aria-label="Play time">
      <Text size="sm">
        A batch of {t.batch} takes {formatSeconds(t.total_seconds)}
        {t.city === 'Anywhere' ? '' : ` in ${t.city}`}: <PerHour copper={t.per_hour} />
      </Text>
      <Text size="xs" c="dimmed">
        {breakdownParts(t.breakdown).join(' · ')}
      </Text>
      {t.legs.length > 0 && (
        <List size="xs" spacing={2}>
          {routes(t.legs).map(({ who, legs }, i) => (
            <List.Item key={i}>
              {who && (
                <>
                  <CharacterName name={who} />:{' '}
                </>
              )}
              {legs[0]!.from_name}
              {legs.map((leg, j) => (
                <Fragment key={j}> → {leg.to_name}</Fragment>
              ))}{' '}
              ({formatSeconds(legs.reduce((sum, leg) => sum + leg.seconds, 0))})
            </List.Item>
          ))}
        </List>
      )}
      {others.length > 0 && (
        <Text size="xs">
          By city:{' '}
          {others.map((c, i) => (
            <Fragment key={c.city}>
              {i > 0 && ' · '}
              {c.missing.length ? (
                <Text span inherit c="dimmed">
                  {c.city} (no {stations(c.missing)})
                </Text>
              ) : (
                <>
                  <Text span inherit fw={c.city === result.best_city ? 700 : undefined}>
                    {c.city} {formatSeconds(c.total_seconds)}
                  </Text>{' '}
                  (<PerHour copper={c.per_hour} />)
                </>
              )}
            </Fragment>
          ))}
          {result.best_city && result.best_city !== t.city && ` · quickest in ${result.best_city}`}
        </Text>
      )}
      {t.deployed.length > 0 && (
        <Text size="xs" c="dimmed">
          Needs a {stations(t.deployed, ' and a ')}
        </Text>
      )}
      {t.missing.length > 0 && (
        <Text size="xs" c="red">
          {t.city} has no {stations(t.missing)}: this plan can't be crafted there, and the time leaves it out.
        </Text>
      )}
      {t.unsold.length > 0 && (
        <Text size="xs" c="yellow">
          No vendor in {t.city} sells {t.unsold.map((id) => items[id]?.name ?? `item ${id}`).join(', ')}: timed at
          the nearest vendor.
        </Text>
      )}
    </Stack>
  )
}
