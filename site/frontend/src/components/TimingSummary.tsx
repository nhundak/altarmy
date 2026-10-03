import { Stack, Text } from '@mantine/core'
import type { ItemMap, RankResult } from '../api/client'

/** Station kinds as words: cooking_fire reads "cooking fire". */
const stations = (kinds: readonly string[], joiner = ' or ') => kinds.map((k) => k.replaceAll('_', ' ')).join(joiner)

/**
 * What the plan's lines can't show: the new Forever stations it needs (counted as set down on the spot), a
 * station the city lacks, and vendor items nobody there sells. They come with the server's timing of the plan,
 * whose times themselves are not shown.
 */
export function TimingNotes({ result, items }: { result: RankResult; items: ItemMap }) {
  const t = result.timing
  if (!t || !(t.deployed.length || t.missing.length || t.unsold.length)) return null
  return (
    <Stack gap={4} aria-label="Plan notes">
      {t.deployed.length > 0 && (
        <Text size="xs" c="dimmed">
          Needs a {stations(t.deployed, ' and a ')}
        </Text>
      )}
      {t.missing.length > 0 && (
        <Text size="xs" c="red">
          {t.city} has no {stations(t.missing)}: this plan can't be crafted there.
        </Text>
      )}
      {t.unsold.length > 0 && (
        <Text size="xs" c="yellow">
          No vendor in {t.city} sells {t.unsold.map((id) => items[id]?.name ?? `item ${id}`).join(', ')}.
        </Text>
      )}
    </Stack>
  )
}
