import { Group, Progress, SimpleGrid, Stack, Text, Title } from '@mantine/core'
import type { ItemMap, RankResult } from '../api/client'
import { useAhCut } from '../api/queries'
import { countedOn, floodCheck } from '../lib/selling'
import { EXIT_SHORT } from '../lib/exits'
import { Earned } from './StepList'
import { Money } from './Money'

/** Price levels the panel draws. */
const LEVELS_DRAWN = 6
/** Days of scans before "usually" means anything. */
const USUAL_FROM_DAYS = 3

/** What the market's sales tell, in words: how many were seen sold, over how long it was watched. */
export function seenSold(sold: number, watched: number, pairs: number | null): string {
  if (watched <= 0) return "Sales here aren't watched yet: nobody has scanned twice within 30 minutes lately"
  const hours = `${watched} ${watched === 1 ? 'hour' : 'hours'} watched`
  if (sold === 0) return `None seen sold in ${hours}`
  if ((pairs ?? 0) <= 1) return `${sold} seen sold in ${hours}, all between one pair of scans: maybe a single buyer`
  return `At least ${sold} seen sold in ${hours}, over ${pairs} scan pairs`
}

/**
 * Why this sale: the market for what is sold (what is asked, what it usually goes for, what the plan counted on), the
 * price levels listed (just listed ones marked, those plans don't count on greyed), what was seen sold against how long
 * the house was watched, every way to sell with its profit, and for a disenchant each material with what the session
 * adds to its market.
 */
export function MarketPanel({ result: r, items }: { result: RankResult; items: ItemMap }) {
  useAhCut() // loads the versions with the panel, for the sell step's prices
  const item = items[r.output_item_id]
  const counted = countedOn(r, items)
  const levels = (item?.ah_levels ?? []).slice(0, LEVELS_DRAWN)
  const most = Math.max(1, ...levels.map((l) => l.quantity))
  const watched = r.confidence?.watched_hours ?? 0
  const flood = floodCheck(r, items)
  const best = Math.max(1, ...r.sell_options.map((o) => Math.abs(o.profit)))
  return (
    <section aria-label="Why this?">
      <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
        <Stack gap={4}>
          <Title order={6}>The market for {r.output_name}</Title>
          {item && item.ah_price != null ? (
            <>
              <Text size="sm">
                {item.market_price != null && (
                  <>
                    Asking now <Money copper={item.market_price} /> ·{' '}
                  </>
                )}
                cheapest <Money copper={item.ah_price} />
              </Text>
              <Text size="sm">
                {item.median_7d != null && (item.scans_7d ?? 0) >= USUAL_FROM_DAYS ? (
                  <>
                    Usually <Money copper={item.median_7d} /> ({item.scans_7d} days)
                  </>
                ) : (
                  'Too new to tell what it usually goes for'
                )}
                {counted.price != null && (
                  <>
                    {' '}
                    · we count on <Money copper={counted.price} /> for {counted.units} of your {counted.of}
                  </>
                )}
              </Text>
              {item.ah_quantity != null && <Text size="sm">{item.ah_quantity.toLocaleString()} listed</Text>}
              {levels.map((l) => (
                <Group key={l.price} gap="xs" wrap="nowrap" opacity={l.counted ? 1 : 0.5}>
                  <Text size="xs" w={70} ta="right" ff="monospace">
                    <Money copper={l.price} />
                  </Text>
                  <Progress value={(100 * l.quantity) / most} size="sm" w={100} aria-hidden />
                  <Text size="xs" c="dimmed">
                    {l.quantity}
                    {l.more ? ' more' : ''}
                    {l.age === 0 ? ' · just listed' : ` · listed for ${l.age + 1} scans`}
                    {l.counted ? '' : ' (not counted on)'}
                  </Text>
                </Group>
              ))}
              <Text size="sm">{seenSold(item.sold_7d, watched, item.sold_pairs_7d ?? null)}</Text>
            </>
          ) : (
            <Text size="sm" c="dimmed">
              Nothing known of it on this realm&apos;s auction house.
            </Text>
          )}
        </Stack>
        <Stack gap={4}>
          <Title order={6}>Other ways to sell</Title>
          {r.sell_options.map((o) => (
            <Group key={o.kind} gap="xs" wrap="nowrap">
              <Text size="sm" w={110}>
                {EXIT_SHORT[o.kind] ?? o.kind}
              </Text>
              <Text size="sm" ff="monospace" w={90}>
                <Earned copper={o.profit} minus />
              </Text>
              <Progress
                value={(100 * Math.abs(o.profit)) / best}
                color={o.profit < 0 ? 'red' : 'teal'}
                size="sm"
                w={80}
                aria-hidden
              />
            </Group>
          ))}
          {r.excess_units > 0 && (
            <Text size="xs" c="dimmed">
              The market has taken about {r.depth_units} lately: the other {r.excess_units} are counted at{' '}
              {EXIT_SHORT[r.likely_exit === 'ah' ? 'vendor' : r.likely_exit] ?? 'the next best way'}.
            </Text>
          )}
          {flood.map((f) => (
            <Text key={f.itemId} size="xs" c="dimmed">
              Disenchanting adds ~{f.adds} {f.name}
              {f.listed != null && ` to the ${f.listed.toLocaleString()} listed`}
            </Text>
          ))}
        </Stack>
      </SimpleGrid>
    </section>
  )
}
