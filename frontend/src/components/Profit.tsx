import { useEffect, useRef, useState } from 'react'
import { Anchor, Button, Code, Group, Loader, Stack, Text, UnstyledButton } from '@mantine/core'
import { useDisclosure } from '@mantine/hooks'
import { notifications } from '@mantine/notifications'
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from 'motion/react'
import { z } from 'zod'
import type { CharacterGroup, Characters, UploadResult } from '../api/client'
import { useCharacters } from '../api/queries'
import { CharacterList } from './CharacterList'
import { age, parseUtc } from '../lib/age'
import { realmLabel } from '../lib/realms'
import { linkProps, previousRoute } from '../lib/router'
import { useSession } from '../lib/session'
import { useStoredState } from '../lib/storage'
import { Hero } from './Hero'
import { AUTO_IMPORT_CARD, AutoImportBody } from './AutoImport'
import cards from './Cards.module.css'
import { IconChevron, IconCompass, IconDownload, IconPaste } from './icons'
import classes from './Profit.module.css'
import { PasteForm } from './PasteForm'
import { SearchTab } from './SearchTab'
import { type CardSpec, EASE, type Phase, StartCard } from './StartCard'

type CardKey = 'import' | 'auto' | 'browse'

const landingSchema = z.object({ browsed: z.boolean() })
const NOT_BROWSED = { browsed: false }
const NO_GROUPS: readonly CharacterGroup[] = []
/** Alt Army Sync counts as set up while it has uploaded anything within this many days. */
const AUTO_IMPORT_DAYS = 30

/** Whether Alt Army Sync (or the CLI watcher) is uploading for the user: it sent something recently. */
function autoImportOn(lastAt: string | null | undefined, now: Date = new Date()): boolean {
  if (!lastAt) return false
  return now.getTime() - parseUtc(lastAt) < AUTO_IMPORT_DAYS * 86_400_000
}

const CARDS: readonly CardSpec<CardKey>[] = [
  {
    key: 'import',
    title: 'Import your characters',
    blurb:
      "Paste one line from the Alt Army addon: every alt's professions and learned recipes, so results show who crafts what and what mailing reagents between them costs.",
    short: 'Paste the Alt Army export.',
    icon: <IconPaste />,
    recommended: true,
  },
  AUTO_IMPORT_CARD,
  {
    key: 'browse',
    title: 'Skip for now',
    blurb: 'See the most profitable recipes on a realm right now. You can add characters any time.',
    short: 'Every recipe, no character optimization.',
    icon: <IconCompass />,
  },
]

/** The third card once the user has characters: it no longer offers browsing without them, only moving on. */
const CONTINUE: CardSpec<CardKey> = {
  key: 'browse',
  title: 'Continue',
  blurb: 'Done adding characters.',
  short: 'Done adding characters.',
  icon: <IconCompass />,
}

/** The three start cards for a user with or without characters. */
function cardsFor(hasCharacters: boolean): readonly CardSpec<CardKey>[] {
  return hasCharacters ? CARDS.map((c) => (c.key === 'browse' ? CONTINUE : c)) : CARDS
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

/**
 * Once started: what the search works with (how many characters, when they were gathered, whether auto-import is
 * on; it opens to show every character), and ways to change it.
 */
function Strip({ data, onOpen }: { data: Characters | undefined; onOpen: (k: CardKey) => void }) {
  const [details, { toggle }] = useDisclosure(false)
  const groups = data?.groups ?? NO_GROUPS
  const count = groups.reduce((n, g) => n + g.characters.length, 0)
  const auto = autoImportOn(data?.auto_import_at)
  const counted = `${count} ${count === 1 ? 'character' : 'characters'}`
  const updated = data?.imported_at ? `updated ${age(data.imported_at)}` : null
  const autoText = `Auto-import ${auto ? 'on' : 'off'}`
  const dot = (
    <Text span c="dimmed" size="sm" aria-hidden>
      {' · '}
    </Text>
  )
  return (
    <motion.div
      className={cards.strip}
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      transition={{ duration: 0.25 }}
    >
      <Group justify="space-between" gap="sm">
        {count > 0 ? (
          <UnstyledButton
            className={classes.summary}
            onClick={toggle}
            aria-expanded={details}
            aria-controls="your-characters"
            aria-label={[counted, updated, autoText].filter(Boolean).join(', ')}
          >
            <Text size="sm" span>
              <b>{counted}</b>
              {updated && (
                <>
                  {dot}
                  <Text span c="dimmed" size="sm">
                    {updated}
                  </Text>
                </>
              )}
              {dot}
              <Text span size="sm" c={auto ? 'green' : 'dimmed'}>
                {autoText}
              </Text>
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
          <Button size="xs" variant="default" leftSection={<IconDownload size={16} />} onClick={() => onOpen('auto')}>
            Auto-import
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
 * The Profit page: the welcome banner and three ways to start (paste an import, set up the auto-import, skip) and,
 * once the visitor has characters or skipped, the search (which starts by asking for their goal) in their place. Whether they browsed is remembered per user;
 * having characters comes from the server, so another browser's import counts too.
 */
export function ProfitPage() {
  const { uid } = useSession()
  const characters = useCharacters()
  const [landing, setLanding] = useStoredState(`altarmy-profit.landing.${uid}`, landingSchema, NOT_BROWSED)
  const [open, setOpen] = useState<CardKey | null>(null)
  const reduced = useReducedMotion()
  const searchRef = useRef<HTMLElement>(null)
  const shownBefore = useRef<boolean | null>(null)

  const groups = characters.data?.groups ?? NO_GROUPS
  const started = groups.length > 0 || landing.browsed
  const phase: Phase = open ? 'expanded' : started ? 'collapsed' : 'choose'
  const ready = characters.data !== undefined
  // Arriving from the main page, its card turns into the banner, so the banner is there at once (not after the
  // characters load) and folds away once they show the visitor has already started.
  const [carried] = useState(() => previousRoute() === '/')
  const showHero = (ready && !started) || (carried && !ready)

  // Bring the search into view when it first appears, not when the page loads with it.
  useEffect(() => {
    if (!ready) return
    if (shownBefore.current === false && started) {
      searchRef.current?.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' })
    }
    shownBefore.current = started
  }, [ready, started, reduced])

  // Alt Army Sync's first upload brings characters in while its card is open (the status poll notices): move on.
  const hadCharacters = useRef(false)
  useEffect(() => {
    if (!ready) return
    const has = groups.length > 0
    if (has && !hadCharacters.current && open === 'auto') {
      setOpen(null)
      const count = groups.reduce((n, g) => n + g.characters.length, 0)
      notifications.show({
        color: 'green',
        title: 'Characters uploaded',
        message: `${count} ${count === 1 ? 'character' : 'characters'} on ${groups.map((g) => realmLabel(g)).join(', ')}.`,
      })
    }
    hadCharacters.current = has
  }, [ready, groups, open])

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
      <AnimatePresence initial={false}>
        {showHero && (
          <motion.div
            key="hero"
            layoutId="showcase-profit"
            layout
            exit={{ opacity: 0, height: 0, marginBottom: 'calc(-1 * var(--mantine-spacing-lg))' }}
            transition={{ duration: 0.3, ease: EASE }}
            // The banner's radius, so Motion keeps its corners round while the main page's card resizes into it.
            style={{ overflow: 'hidden', borderRadius: 12 }}
          >
            <Hero />
          </motion.div>
        )}
      </AnimatePresence>
      {!ready ? (
        <Group justify="center" py="xl">
          <Loader aria-label="Loading your characters" />
        </Group>
      ) : (
        <LayoutGroup>
          <AnimatePresence mode="wait" initial={false}>
            {phase === 'collapsed' ? (
              <Strip key="strip" data={characters.data} onOpen={setOpen} />
            ) : (
              <motion.div
                key="cards"
                className={cards.cards}
                data-phase={phase}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0, transition: { duration: 0.15 } }}
                role="group"
                aria-label="Ways to start"
              >
                {cardsFor(groups.length > 0).map((spec) => (
                  <StartCard
                    key={spec.key}
                    spec={spec}
                    phase={phase}
                    open={open === spec.key}
                    onPick={() => pick(spec.key)}
                    onClose={() => setOpen(null)}
                  >
                    {spec.key === 'import' && <ImportBody onImported={imported} />}
                    {spec.key === 'auto' && <AutoImportBody />}
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
