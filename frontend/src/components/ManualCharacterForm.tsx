import { useState } from 'react'
import {
  ActionIcon,
  Alert,
  Autocomplete,
  Button,
  Group,
  NumberInput,
  SegmentedControl,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
} from '@mantine/core'
import type { ManualCharacter } from '../api/client'
import { useCharacters, useCoverage, useCreateCharacter, useProfessions } from '../api/queries'
import { realmNames } from '../lib/realms'
import { CLASSES } from '../lib/wow'

type Faction = ManualCharacter['faction']
type Row = { key: number; name: string | null; rank: number | string }

const MAX_LEVEL = 60
const MAX_SKILL = 300

/** A character typed in by hand: realm, name, class, level and professions with their skill. */
export function ManualCharacterForm({ onCreated }: { onCreated?: (c: ManualCharacter) => void }) {
  const professions = useProfessions()
  const characters = useCharacters()
  const coverage = useCoverage()
  const create = useCreateCharacter()
  const selection = characters.data?.selection
  const [realm, setRealm] = useState(selection?.realm ?? '')
  const [faction, setFaction] = useState<Faction>(selection?.faction === 'Alliance' ? 'Alliance' : 'Horde')
  const [name, setName] = useState('')
  const [classFile, setClassFile] = useState<string | null>(null)
  const [level, setLevel] = useState<number | string>(MAX_LEVEL)
  const [rows, setRows] = useState<Row[]>([{ key: 0, name: null, rank: 1 }])

  const setRow = (key: number, change: Partial<Row>) => setRows((rs) => rs.map((r) => (r.key === key ? { ...r, ...change } : r)))
  const picked = new Set(rows.map((r) => r.name))
  const chosen = rows.filter((r): r is Row & { name: string } => r.name !== null)
  const ready = realm.trim() !== '' && name.trim() !== '' && classFile !== null && typeof level === 'number'

  const submit = () => {
    if (!ready || classFile === null || typeof level !== 'number') return
    const body: ManualCharacter = {
      realm: realm.trim(),
      faction,
      name: name.trim(),
      class_file: classFile,
      level,
      professions: chosen.map((r) => ({ name: r.name, rank: typeof r.rank === 'number' ? r.rank : 1 })),
    }
    create.mutate(body, { onSuccess: () => onCreated?.(body) })
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        submit()
      }}
    >
      <Stack gap="sm">
        <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
          <TextInput label="Name" value={name} onChange={(e) => setName(e.currentTarget.value)} required maxLength={64} />
          <Select
            label="Class"
            placeholder="Pick a class"
            data={CLASSES.map((c) => ({ value: c.file, label: c.name }))}
            value={classFile}
            onChange={setClassFile}
            required
          />
          <Autocomplete
            label="Realm"
            placeholder="Your realm"
            data={realmNames(characters.data?.groups ?? [], coverage.data ?? [])}
            value={realm}
            onChange={setRealm}
            required
            maxLength={64}
          />
          <NumberInput label="Level" min={1} max={MAX_LEVEL} clampBehavior="strict" value={level} onChange={setLevel} required />
        </SimpleGrid>
        <Stack gap={4}>
          <Text size="sm" fw={500}>
            Faction
          </Text>
          <SegmentedControl
            aria-label="Faction"
            data={['Horde', 'Alliance']}
            value={faction}
            onChange={(v) => setFaction(v === 'Alliance' ? 'Alliance' : 'Horde')}
          />
        </Stack>
        <Stack gap="xs">
          <Text size="sm" fw={500}>
            Professions
          </Text>
          {rows.map((r, i) => (
            <Group key={r.key} gap="xs" wrap="nowrap" align="flex-end">
              <Select
                aria-label={`Profession ${i + 1}`}
                placeholder="Profession"
                data={(professions.data ?? []).map((p) => ({ value: p, label: p, disabled: p !== r.name && picked.has(p) }))}
                value={r.name}
                onChange={(v) => setRow(r.key, { name: v })}
                searchable
                style={{ flex: 1 }}
              />
              <NumberInput
                aria-label={`Skill ${i + 1}`}
                min={1}
                max={MAX_SKILL}
                clampBehavior="strict"
                value={r.rank}
                onChange={(v) => setRow(r.key, { rank: v })}
                w={96}
              />
              <ActionIcon
                variant="subtle"
                color="gray"
                size="lg"
                aria-label={`Remove profession ${i + 1}`}
                onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))}
              >
                ✕
              </ActionIcon>
            </Group>
          ))}
          <Group>
            <Button
              variant="subtle"
              size="compact-sm"
              onClick={() => setRows((rs) => [...rs, { key: Math.max(0, ...rs.map((x) => x.key)) + 1, name: null, rank: 1 }])}
            >
              + Add a profession
            </Button>
          </Group>
        </Stack>
        <Text size="xs" c="dimmed">
          A hand-made character knows every recipe of its professions. Importing from Alt Army later replaces every
          character, including ones added here.
        </Text>
        {create.isError && <Alert color="red">{create.error.message}</Alert>}
        <Group justify="flex-end">
          <Button type="submit" disabled={!ready} loading={create.isPending}>
            Add character
          </Button>
        </Group>
      </Stack>
    </form>
  )
}
