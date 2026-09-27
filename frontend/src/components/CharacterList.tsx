import { Box, Text } from '@mantine/core'
import { Fragment } from 'react'
import type { CharacterGroup } from '../api/client'
import { realmLabel } from '../lib/realms'
import { CharacterName } from './CharacterName'

/** Highest level first; equal levels by name. */
function byLevel(characters: CharacterGroup['characters']) {
  return [...characters].sort((a, b) => b.level - a.level || a.name.localeCompare(b.name))
}

/** Each realm/faction's characters in aligned columns: name, level, profession skills (and Legacy talents). */
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
                {c.professions.map((p) => `${p.name} ${p.rank}/${p.max_rank}`).join(', ')}
                {c.talents.length > 0 &&
                  `${c.professions.length ? ' · ' : ''}${c.talents.map((t) => `${t.name} ${t.rank}/${t.max_rank}`).join(', ')}`}
              </Text>
            </Fragment>
          ))}
        </Fragment>
      ))}
    </Box>
  )
}
