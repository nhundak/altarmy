import { useEffect, useState, type ReactNode } from 'react'
import { Button, Combobox, Group, InputBase, Stack, Text, Tooltip, useCombobox } from '@mantine/core'
import type { Selection } from '../api/client'
import { useMaxSkill } from '../api/queries'
import { age } from '../lib/age'
import { fromKey, toKey } from '../lib/realms'
import { filterRealmSkills, type Holder, type RealmSkills } from '../lib/setup'
import { talentNote } from '../lib/talents'
import { classWord } from '../lib/wow'
import cards from './Cards.module.css'
import { CharacterName } from './CharacterName'
import classes from './ClimberCard.module.css'
import { IconPaste } from './icons'
import { ProfessionIcon } from './ProfessionIcon'
import { SkillBar } from './SkillBar'

/** "Frell's", "Frell Ofelements'". */
const possessive = (name: string) => (name.endsWith('s') ? `${name}'` : `${name}'s`)

/** Joins and splits a realm, character and profession as one option's value (none holds a line break). */
const optionValue = (realm: Selection, character: string, profession: string) =>
  `${toKey(realm)}\n${character}\n${profession.toLowerCase()}`

/** Who skills up what (`children`), looking like a select across its card: it opens a search over every character's
 * professions to switch to, grouped by realm and faction, then by character, all alphabetically, each profession a row
 * (icon, name, skill out of the highest there is), the current one marked. Typing narrows it to the realms, characters
 * or professions whose name holds what was typed. */
function ClimberSelect({
  realm,
  climber,
  profession,
  realms,
  onSwitch,
  children,
}: {
  realm: Selection
  climber: string
  profession: string
  realms: readonly RealmSkills[]
  onSwitch: (realm: Selection, profession: string, character: string) => void
  children: ReactNode
}) {
  const [search, setSearch] = useState('')
  const combobox = useCombobox({
    onDropdownClose: () => {
      combobox.resetSelectedOption()
      setSearch('')
    },
    onDropdownOpen: () => combobox.focusSearchInput(),
  })
  // every bar against the profession's highest skill, not the rank trained so far
  const maxSkill = useMaxSkill()
  const shown = filterRealmSkills(realms, search)
  const current = optionValue(realm, climber, profession)
  // What Enter would pick, highlighted for the arrow keys to move from: the current option on opening, the first match
  // while searching. After the options render (the dropdown's content mounts after it opens).
  // (The store is a new object every render, its callbacks aren't: a re-render mid-way must not move the highlight.)
  const { dropdownOpened: opened, selectFirstOption, selectActiveOption } = combobox
  useEffect(() => {
    if (!opened) return
    const timer = setTimeout(() => (search.trim() ? selectFirstOption() : selectActiveOption()), 0)
    return () => clearTimeout(timer)
  }, [opened, search, selectFirstOption, selectActiveOption])
  return (
    <Combobox
      store={combobox}
      width="target"
      position="bottom-start"
      withinPortal
      shadow="md"
      classNames={{ option: classes.option }}
      onOptionSubmit={(value) => {
        combobox.closeDropdown()
        if (value === current) return
        const [key = '', character = ''] = value.split('\n')
        const r = realms.find((x) => toKey(x.realm) === key)
        const name = r?.characters.find((c) => c.name === character)?.professions.find(
          (p) => optionValue(r.realm, character, p.name) === value,
        )?.name
        if (name) onSwitch(fromKey(key), name, character)
      }}
    >
      <Combobox.Target targetType="button">
        <InputBase
          component="button"
          type="button"
          pointer
          rightSection={<Combobox.Chevron />}
          rightSectionPointerEvents="none"
          onClick={() => combobox.toggleDropdown()}
          aria-label="Switch character or profession"
          classNames={{ input: classes.select }}
        >
          <Group component="span" gap="sm" wrap="nowrap" justify="space-between" w="100%">
            {children}
          </Group>
        </InputBase>
      </Combobox.Target>
      <Combobox.Dropdown>
        <Combobox.Search
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          placeholder="Search characters or professions"
          aria-label="Search characters or professions"
          onKeyDown={(e) => {
            // Tab closes it and goes back to the select, where the next Tab carries on from (the arrow keys move
            // through the options)
            if (e.key !== 'Tab') return
            e.preventDefault()
            combobox.closeDropdown()
            combobox.focusTarget()
          }}
        />
        {/* not a Tab stop of its own, as a scrolling box otherwise is */}
        <Combobox.Options mah={360} style={{ overflowY: 'auto' }} tabIndex={-1}>
          {shown.length === 0 && <Combobox.Empty>Nothing matches</Combobox.Empty>}
          {shown.map((r) => (
            <Combobox.Group key={toKey(r.realm)} label={r.label}>
              {r.characters.map((c) => (
                <div key={c.name} role="group" aria-label={c.name}>
                  {/* one block: a flex box would drop the space before the parenthesis */}
                  <div className={classes.character}>
                    <CharacterName name={c.name} classFile={c.classFile} /> (level {c.level} {classWord(c.classFile)})
                  </div>
                  {c.professions.map((p) => {
                    const value = optionValue(r.realm, c.name, p.name)
                    const active = value === current
                    return (
                      <Combobox.Option key={value} value={value} active={active} aria-selected={active}>
                        <div className={classes.row} data-active={active || undefined}>
                          <ProfessionIcon profession={p.name} />
                          <span>{p.name}</span>
                          <SkillBar rank={p.rank} maxRank={maxSkill} label={`${c.name}'s ${p.name}`} aligned />
                        </div>
                      </Combobox.Option>
                    )
                  })}
                </div>
              ))}
            </Combobox.Group>
          ))}
        </Combobox.Options>
      </Combobox.Dropdown>
    </Combobox>
  )
}

/**
 * The skill page's top-left card: who skills up what, a select across the card switching to any character's
 * profession on any realm (another realm's switches the search to it); their Legacy talents that help, if any; when the
 * characters were uploaded, and Upload again.
 */
export function ClimberCard({
  realm,
  climber,
  profession,
  realms,
  importedAt,
  onSwitch,
  onUploadAgain,
}: {
  /** the climber's realm and faction */
  realm: Selection
  climber: Holder
  profession: string
  /** every realm's characters and professions, for the select */
  realms: readonly RealmSkills[]
  /** when the characters were uploaded last (UTC); null: unknown */
  importedAt: string | null | undefined
  onSwitch: (realm: Selection, profession: string, character: string) => void
  onUploadAgain: () => void
}) {
  // the bar against the profession's highest skill, not the rank trained so far
  const maxSkill = useMaxSkill()
  return (
    <section className={cards.card} aria-label="Skilling up">
      <Stack gap="sm" className={cards.open} h="100%">
        <ClimberSelect
          realm={realm}
          climber={climber.name}
          profession={profession}
          realms={realms}
          onSwitch={onSwitch}
        >
          <Group component="span" gap={8} wrap="nowrap" miw={0}>
            <ProfessionIcon profession={profession} />
            <Text span size="sm" truncate>
              <CharacterName name={possessive(climber.name)} classFile={climber.classFile} /> {profession}
            </Text>
          </Group>
          <SkillBar rank={climber.rank} maxRank={maxSkill} label={`${climber.name}'s ${profession}`} />
        </ClimberSelect>
        {climber.talents && (
          <Tooltip
            label={
              <Stack gap="xs">
                {climber.talents.map((t) => (
                  <div key={t.spellId}>
                    <Text size="sm" fw={700}>
                      {t.name}
                    </Text>
                    <Text size="sm">
                      Rank {t.rank}/{t.maxRank}
                    </Text>
                    <Text size="sm">{talentNote(t)}</Text>
                  </div>
                ))}
              </Stack>
            }
            multiline
            w={260}
            withArrow
          >
            <Text size="sm" c="dimmed" className={classes.hint}>
              {climber.talents.map((t) => `${t.rank}/${t.maxRank} ${t.name}`).join(', ')}
            </Text>
          </Tooltip>
        )}
        {/* at the foot of the card, however tall the row makes it */}
        <Group justify="space-between" gap="sm" mt="auto">
          <Text size="sm" c="dimmed">
            {importedAt ? `Updated ${age(importedAt)}` : ''}
          </Text>
          <Button size="xs" variant="light" leftSection={<IconPaste size={16} />} onClick={onUploadAgain}>
            Upload again
          </Button>
        </Group>
      </Stack>
    </section>
  )
}
