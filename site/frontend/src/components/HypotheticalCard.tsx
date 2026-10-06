import { useEffect, useState } from 'react'
import { Button, Group, NumberInput, Select, Stack, Text } from '@mantine/core'
import { useDebouncedValue } from '@mantine/hooks'
import { useMaxSkill } from '../api/queries'
import cards from './Cards.module.css'
import { IconPaste } from './icons'
import { ProfessionIcon } from './ProfessionIcon'
import { SkillBar } from './SkillBar'

/**
 * The skill page's top-left card for a character nobody uploaded: which profession they skill up (a select over every
 * one with recipes) from what skill (typed; applied once settled), what is assumed about them, and Upload your
 * characters, for a climb of their own.
 */
export function HypotheticalCard({
  profession,
  skill,
  professions,
  onChange,
  onUpload,
}: {
  profession: string
  skill: number
  /** every profession that can be skilled up, by name */
  professions: readonly string[]
  /** another profession, or another starting skill */
  onChange: (profession: string, skill: number) => void
  onUpload: () => void
}) {
  const maxSkill = useMaxSkill()
  const [typed, setTyped] = useState<number | string>(skill)
  // applied only within 1 and the highest skill: what is typed on the way there changes nothing
  const valid = typeof typed === 'number' && typed >= 1 && typed <= maxSkill ? Math.round(typed) : null
  const [settled] = useDebouncedValue(valid, 400)
  useEffect(() => {
    if (settled !== null && settled !== skill) onChange(profession, settled)
  }, [settled, skill, profession, onChange])
  return (
    <section className={cards.card} aria-label="Skilling up">
      <Stack gap="sm" className={cards.open} h="100%">
        <Group gap="sm" wrap="nowrap" align="flex-end">
          <Select
            label="Profession"
            aria-label="Profession"
            leftSection={<ProfessionIcon profession={profession} />}
            data={professions.map((name) => ({ value: name, label: name }))}
            // each option after the game's icon of its profession, as the profession cards are
            renderOption={({ option }) => (
              <Group gap="xs" wrap="nowrap">
                <ProfessionIcon profession={option.value} />
                <span>{option.label}</span>
              </Group>
            )}
            value={profession}
            onChange={(name) => name && name !== profession && onChange(name, skill)}
            allowDeselect={false}
            size="sm"
            miw={0}
            style={{ flex: 1 }}
          />
          <NumberInput
            label="Current skill"
            min={1}
            max={maxSkill}
            step={1}
            allowDecimal={false}
            value={typed}
            onChange={setTyped}
            size="sm"
            w={110}
          />
        </Group>
        <SkillBar rank={skill} maxRank={maxSkill} label={`Your ${profession}`} />
        {/* at the foot of the card, however tall the row makes it */}
        <Group justify="space-between" gap="sm" wrap="nowrap" mt="auto">
          <Text size="sm" c="dimmed">
            Doing our best with no character data. Upload your characters for more accurate recommendations
          </Text>
          <Button size="xs" variant="light" leftSection={<IconPaste size={16} />} onClick={onUpload} flex="none">
            Upload your characters
          </Button>
        </Group>
      </Stack>
    </section>
  )
}
