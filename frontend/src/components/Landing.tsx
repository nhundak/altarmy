import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Anchor, Badge, Button, CloseButton, Code, Group, Loader, Stack, Text, Title, UnstyledButton } from '@mantine/core'
import { useDisclosure } from '@mantine/hooks'
import { notifications } from '@mantine/notifications'
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from 'motion/react'
import { z } from 'zod'
import type { CharacterGroup, UploadResult } from '../api/client'
import { useCharacters } from '../api/queries'
import { CharacterList } from './CharacterList'
import { realmLabel } from '../lib/realms'
import { linkProps } from '../lib/router'
import { useSession } from '../lib/session'
import { useStoredState } from '../lib/storage'
import { Hero } from './Hero'
import { IconChevron, IconCompass, IconPaste, IconUserPlus } from './icons'
import classes from './Landing.module.css'
import { ManualCharacterForm } from './ManualCharacterForm'
import { PasteForm } from './PasteForm'
import { SearchTab } from './SearchTab'

type CardKey = 'import' | 'manual' | 'browse'
type Phase = 'choose' | 'expanded' | 'collapsed'

const EASE = [0.25, 0.8, 0.25, 1] as const
const LAYOUT = { layout: { duration: 0.35, ease: EASE } }

const landingSchema = z.object({ browsed: z.boolean() })
const NOT_BROWSED = { browsed: false }

type CardSpec = { key: CardKey; title: string; blurb: string; short: string; icon: ReactNode }

const CARDS: readonly CardSpec[] = [
  {
    key: 'import',
    title: 'Import your characters',
    blurb:
      "Paste one line from the Alt Army addon: every alt's professions and learned recipes, so results show who crafts what and what mailing reagents between them costs.",
    short: 'Paste the Alt Army export.',
    icon: <IconPaste />,
  },
  {
    key: 'manual',
    title: 'Create manually',
    blurb: 'No addon? Type in a character: class, level and profession skills.',
    short: 'Type in a character.',
    icon: <IconUserPlus />,
  },
  {
    key: 'browse',
    title: 'Just browse',
    blurb: 'See the most profitable recipes on a realm right now, no characters needed.',
    short: 'Every recipe, no characters.',
    icon: <IconCompass />,
  },
]

/** One of the three ways to start: a big button while choosing, a form once opened, a small button beside it. */
function StartCard({
  spec,
  phase,
  open,
  onPick,
  onClose,
  children,
}: {
  spec: CardSpec
  phase: Phase
  open: boolean
  onPick: () => void
  onClose: () => void
  children?: ReactNode
}) {
  const compact = phase === 'expanded' && !open
  return (
    <motion.div
      layout
      transition={LAYOUT}
      className={classes.slot}
      data-open={open || undefined}
      style={{ borderRadius: 12 }}
    >
      <motion.div
        layout
        transition={LAYOUT}
        className={classes.card}
        data-featured={(spec.key === 'import' && !compact) || undefined}
        style={{ borderRadius: 12 }}
      >
        {open ? (
          <motion.div layout="position" className={classes.open}>
            <Group justify="space-between" align="flex-start" wrap="nowrap" mb="md">
              <Group gap="sm" wrap="nowrap">
                <span className={classes.icon}>{spec.icon}</span>
                <Title order={3}>{spec.title}</Title>
              </Group>
              <CloseButton aria-label="Back to the three ways to start" onClick={onClose} />
            </Group>
            <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25, delay: 0.1 }}>
              {children}
            </motion.div>
          </motion.div>
        ) : (
          <UnstyledButton className={classes.pick} onClick={onPick} aria-label={spec.title}>
            <motion.div layout="position" className={compact ? classes.compact : undefined}>
              {compact ? (
                <Group gap="sm" wrap="nowrap">
                  <span className={classes.icon}>{spec.icon}</span>
                  <Stack gap={0}>
                    <Text fw={700}>{spec.title}</Text>
                    <Text size="sm" c="dimmed">
                      {spec.short}
                    </Text>
                  </Stack>
                </Group>
              ) : (
                <Stack gap="sm">
                  <Group justify="space-between" align="flex-start">
                    <span className={classes.icon}>{spec.icon}</span>
                    {spec.key === 'import' && (
                      <Badge variant="light" size="sm">
                        Recommended
                      </Badge>
                    )}
                  </Group>
                  <Title order={3}>{spec.title}</Title>
                  <Text size="sm" c="dimmed">
                    {spec.blurb}
                  </Text>
                </Stack>
              )}
            </motion.div>
          </UnstyledButton>
        )}
      </motion.div>
    </motion.div>
  )
}

function ImportBody({ onImported }: { onImported: (r: UploadResult) => void }) {
  return (
    <Stack gap="md">
      <ol className={classes.steps}>
        <li>
          Install the Alt Army addon (<Anchor {...linkProps('/addon')}>Get the Addon</Anchor>) and log in to each character
          once.
        </li>
        <li>
          In game, type <Code>/altarmy export</Code> and press Ctrl+C.
        </li>
        <li>Paste it here.</li>
      </ol>
      <PasteForm onImported={onImported} autoFocus />
    </Stack>
  )
}

/** Once started: what the search works with (its characters open to show their details), and ways to change it. */
function Strip({ groups, onOpen }: { groups: readonly CharacterGroup[]; onOpen: (k: CardKey) => void }) {
  const [details, { toggle }] = useDisclosure(false)
  const count = groups.reduce((n, g) => n + g.characters.length, 0)
  return (
    <motion.div
      className={classes.strip}
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      transition={{ duration: 0.25 }}
    >
      <Group justify="space-between" gap="sm">
        {count > 0 ? (
          <UnstyledButton className={classes.summary} onClick={toggle} aria-expanded={details} aria-controls="your-characters">
            <Text size="sm" span>
              <b>
                {count} {count === 1 ? 'character' : 'characters'}
              </b>{' '}
              on {groups.map((g) => realmLabel(g)).join(', ')}
            </Text>
            <span className={classes.chevron} data-open={details || undefined}>
              <IconChevron size={16} />
            </span>
          </UnstyledButton>
        ) : (
          <Text size="sm">
            <b>Browsing every recipe.</b>{' '}
            <Text span c="dimmed" size="sm">
              Add characters to see what they can craft and what mailing between them costs.
            </Text>
          </Text>
        )}
        <Group gap="xs">
          <Button size="xs" variant="light" leftSection={<IconPaste size={16} />} onClick={() => onOpen('import')}>
            {count > 0 ? 'Import again' : 'Import your characters'}
          </Button>
          <Button size="xs" variant="default" leftSection={<IconUserPlus size={16} />} onClick={() => onOpen('manual')}>
            Add a character
          </Button>
        </Group>
      </Group>
      <AnimatePresence initial={false}>
        {details && count > 0 && (
          <motion.div
            key="details"
            id="your-characters"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.25, ease: EASE }}
            style={{ overflow: 'hidden' }}
          >
            <div className={classes.details}>
              <CharacterList groups={groups} />
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  )
}

/**
 * The main page: the welcome banner, three ways to start (import, create by hand, just browse) and, once the visitor
 * has characters or chose to browse, the search below. Whether they browsed is remembered per user; having
 * characters comes from the server, so another browser's import counts too.
 */
export function Landing() {
  const { uid } = useSession()
  const characters = useCharacters()
  const [landing, setLanding] = useStoredState(`altarmy-profit.landing.${uid}`, landingSchema, NOT_BROWSED)
  const [open, setOpen] = useState<CardKey | null>(null)
  const reduced = useReducedMotion()
  const searchRef = useRef<HTMLElement>(null)
  const shownBefore = useRef<boolean | null>(null)

  const groups = characters.data?.groups ?? []
  const started = groups.length > 0 || landing.browsed
  const phase: Phase = open ? 'expanded' : started ? 'collapsed' : 'choose'
  const ready = characters.data !== undefined

  // Bring the search into view when it first appears, not when the page loads with it.
  useEffect(() => {
    if (!ready) return
    if (shownBefore.current === false && started) {
      searchRef.current?.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' })
    }
    shownBefore.current = started
  }, [ready, started, reduced])

  const pick = (key: CardKey) => {
    if (key === 'browse') {
      setLanding({ browsed: true })
      setOpen(null)
    } else {
      setOpen(key)
    }
  }

  const imported = (r: UploadResult) => {
    setOpen(null)
    notifications.show({
      color: 'green',
      title: 'Characters imported',
      message: `${r.characters} ${r.characters === 1 ? 'character' : 'characters'}${
        r.groups.length ? ` on ${r.groups.map((g) => realmLabel(g)).join(', ')}` : ''
      }.`,
    })
  }

  return (
    <Stack gap="lg">
      <Hero compact={started && !open} />
      {!ready ? (
        <Group justify="center" py="xl">
          <Loader aria-label="Loading your characters" />
        </Group>
      ) : (
        <LayoutGroup>
          <AnimatePresence mode="wait" initial={false}>
            {phase === 'collapsed' ? (
              <Strip key="strip" groups={groups} onOpen={setOpen} />
            ) : (
              <motion.div
                key="cards"
                className={classes.cards}
                data-phase={phase}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0, transition: { duration: 0.15 } }}
                role="group"
                aria-label="Ways to start"
              >
                {CARDS.map((spec) => (
                  <StartCard
                    key={spec.key}
                    spec={spec}
                    phase={phase}
                    open={open === spec.key}
                    onPick={() => pick(spec.key)}
                    onClose={() => setOpen(null)}
                  >
                    {spec.key === 'import' && <ImportBody onImported={imported} />}
                    {spec.key === 'manual' && (
                      <ManualCharacterForm
                        onCreated={(c) => {
                          setOpen(null)
                          notifications.show({ color: 'green', title: 'Character added', message: `${c.name} on ${realmLabel(c)}.` })
                        }}
                      />
                    )}
                  </StartCard>
                ))}
              </motion.div>
            )}
          </AnimatePresence>
          <AnimatePresence>
            {started && (
              <motion.section
                key="search"
                ref={searchRef}
                aria-label="Search"
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.35, delay: 0.1, ease: EASE }}
                style={{ scrollMarginTop: 16 }}
              >
                <SearchTab />
              </motion.section>
            )}
          </AnimatePresence>
        </LayoutGroup>
      )}
    </Stack>
  )
}
