import { Badge, Stack, Text, Tooltip } from '@mantine/core'
import type { RankResult } from '../api/client'
import { VERDICT_COLOR, VERDICT_GLYPH, VERDICT_LABEL, verdictTitle, verdictWord } from '../lib/verdict'

/** Whether a sale will sell: a chip (glyph and word, so it reads without colour), its main reason under it, and the
 * whole verdict on hover or focus. */
export function VerdictChip({ result }: { result: Pick<RankResult, 'verdict' | 'verdict_reasons' | 'buy_flags'> }) {
  const word = verdictWord(result)
  return (
    <Tooltip label={verdictTitle(result)} multiline maw={300} withArrow events={{ hover: true, focus: true, touch: true }}>
      <Stack gap={0} align="flex-start" tabIndex={0} aria-label={verdictTitle(result)} style={{ cursor: 'help' }}>
        <Badge variant="light" color={VERDICT_COLOR[result.verdict]} size="sm">
          {VERDICT_GLYPH[result.verdict]} {VERDICT_LABEL[result.verdict]}
        </Badge>
        {word && (
          <Text size="xs" c="dimmed" lineClamp={2} maw={160}>
            {word}
          </Text>
        )}
      </Stack>
    </Tooltip>
  )
}
