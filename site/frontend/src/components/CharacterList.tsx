import { Box, Text } from '@mantine/core'
import { Fragment } from 'react'
import type { CharacterGroup } from '../api/client'
import { realmLabel } from '../lib/realms'
import { CharacterName } from './CharacterName'

/** Highest level first; equal levels by name. */
function byLevel(characters: CharacterGroup['characters']) {
  return [...characters].sort((a, b) => b.level - a.level || a.name.localeCompare(b.name))
}

type Character = CharacterGroup['characters'][number]

/** What the character's reputation takes off at vendors, e.g. "Vendors −10%: Orgrimmar, Thunder Bluff". */
function vendorNote(discounts: Character['vendor_discounts']): string {
  const percents = [...new Set(discounts.map((d) => d.percent))].sort((a, b) => b - a)
  return percents
    .map((p) => `Vendors −${p}%: ${discounts.filter((d) => d.percent === p).map((d) => d.faction).join(', ')}`)
    .join('; ')
}

/** A character's profession skills, Legacy talents and vendor discounts on one line. */
function skills(c: Character): string {
  return [
    c.professions.map((p) => `${p.name} ${p.rank}/${p.max_rank}`).join(', '),
    c.talents.map((t) => `${t.name} ${t.rank}/${t.max_rank}`).join(', '),
    vendorNote(c.vendor_discounts),
  ]
    .filter(Boolean)
    .join(' · ')
}

/**
 * Each realm/faction's characters in aligned columns: name, level, profession skills (and Legacy talents, and
 * what their reputation takes off at vendors).
 */
export function CharacterList({ groups }: { groups: readonly CharacterGroup[] }) {
  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'max-content max-content 1fr',
        columnGap: 'var(--mantine-spacing-md)',
        rowGap: 4,
        alignItems: 'baseline',
      }}
    >
      {groups.map((g, i) => (
        <Fragment key={`${g.realm}\t${g.faction}`}>
          <Text
            size="xs"
            fw={700}
            tt="uppercase"
            c="dimmed"
            style={{ gridColumn: '1 / -1', marginTop: i ? 'var(--mantine-spacing-xs)' : 0 }}
          >
            {realmLabel(g)}
          </Text>
          {byLevel(g.characters).map((c) => (
            <Fragment key={c.name}>
              <Text size="sm" fw={700}>
                <CharacterName name={c.name} classFile={c.class_file} />
              </Text>
              <Text size="sm" c="dimmed" ta="right">
                {c.level}
              </Text>
              <Text size="sm" c="dimmed">
                {skills(c)}
              </Text>
            </Fragment>
          ))}
        </Fragment>
      ))}
    </Box>
  )
}
