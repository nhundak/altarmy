import { Button, Group, Stack, Text } from '@mantine/core'
import type { CharacterGroup } from '../api/client'
import { useDeleteCharacter } from '../api/queries'
import { realmLabel } from '../lib/realms'
import { CharacterName } from './CharacterName'

/** Each realm/faction's characters: level and profession skills, with a way to remove one. */
export function CharacterList({ groups }: { groups: readonly CharacterGroup[] }) {
  const remove = useDeleteCharacter()
  return (
    <Stack gap="sm">
      {groups.map((g) => (
        <Stack key={`${g.realm}\t${g.faction}`} gap={4}>
          <Text size="xs" fw={700} tt="uppercase" c="dimmed">
            {realmLabel(g)}
          </Text>
          {g.characters.map((c) => (
            <Group key={c.name} justify="space-between" wrap="nowrap" gap="xs">
              <Text size="sm">
                <b>
                  <CharacterName name={c.name} classFile={c.class_file} />
                </b>{' '}
                <Text span c="dimmed" size="sm">
                  {c.level}
                  {c.professions.length ? ': ' : ''}
                  {c.professions.map((p) => `${p.name} ${p.rank}/${p.max_rank}`).join(', ')}
                </Text>
              </Text>
              <Button
                size="compact-xs"
                variant="subtle"
                color="gray"
                aria-label={`Remove ${c.name}`}
                loading={remove.isPending && remove.variables.name === c.name}
                onClick={() => remove.mutate({ realm: g.realm, name: c.name })}
              >
                Remove
              </Button>
            </Group>
          ))}
        </Stack>
      ))}
    </Stack>
  )
}
