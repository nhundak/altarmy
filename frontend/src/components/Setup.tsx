import type { ReactNode } from 'react'
import { Button, Group, List, Stack, Text, Title, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion } from 'motion/react'
import {
  AIMS,
  ANY_PROFESSION,
  SELLING,
  STEP_QUESTION,
  stripParts,
  type Aim,
  type Card,
  type Holder,
  type ProfessionChoice,
  type Setup as SetupAnswers,
  type Step,
} from '../lib/setup'
import cards from './Cards.module.css'
import { CharacterName } from './CharacterName'
import classes from './Setup.module.css'
import { IconCoin, IconSteps } from './icons'

const AIM_ICONS: Readonly<Record<Aim, ReactNode>> = {
  gold: <IconCoin />,
  skill: <IconSteps />,
}

const FADE = { initial: { opacity: 0, y: -8 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0, y: -8 } }

/** The answers given so far as small buttons, each opening its question again. */
function Answers({ setup, skip, onOpen }: { setup: SetupAnswers; skip?: Step; onOpen: (step: Step) => void }) {
  const parts = stripParts(setup).filter((p) => p.step !== skip)
  return (
    <Group gap={4} wrap="wrap">
      {parts.map((p, i) => (
        <Group key={p.step} gap={4} wrap="nowrap">
          {i > 0 && (
            <Text span c="dimmed" size="sm" aria-hidden>
              ·
            </Text>
          )}
          <Button size="compact-sm" variant="subtle" onClick={() => onOpen(p.step)}>
            {p.text}
          </Button>
        </Group>
      ))}
    </Group>
  )
}

function OptionCard<K extends string>({
  card,
  icon,
  body,
  picked,
  reason,
  onPick,
}: {
  card: Card<K>
  icon?: ReactNode
  /** Shown instead of the card's blurb. */
  body?: ReactNode
  picked: boolean
  reason?: string
  onPick: () => void
}) {
  return (
    <div className={cards.card} data-featured={picked || undefined} data-disabled={reason !== undefined || undefined}>
      <UnstyledButton
        className={`${cards.pick} ${classes.top}`}
        onClick={onPick}
        aria-label={card.title}
        aria-pressed={picked}
        disabled={reason !== undefined}
      >
        <Stack gap="sm">
          {icon && <span className={cards.icon}>{icon}</span>}
          <Title order={4}>{card.title}</Title>
          {body ?? (
            <Text size="sm" c="dimmed">
              {card.blurb}
            </Text>
          )}
          {card.details && (
            <div>
              <Text size="xs" c="dimmed">
                {card.details}
                {card.caution && (
                  <>
                    {' '}
                    <Text span inherit fw={600} c="orange">
                      {card.caution}
                    </Text>
                  </>
                )}
              </Text>
              {card.points && (
                <List size="xs" c="dimmed" mt={4}>
                  {card.points.map((p) => (
                    <List.Item key={p}>{p}</List.Item>
                  ))}
                </List>
              )}
            </div>
          )}
          {reason && (
            <Text size="sm" fw={500} c="orange">
              {reason}
            </Text>
          )}
        </Stack>
      </UnstyledButton>
    </div>
  )
}

const ANY_CARD: Card<string> = {
  key: ANY_PROFESSION,
  title: 'Any profession',
  blurb: 'Every recipe that gives at least one of your characters a skill point.',
}

/** Who has a profession, one per line: the name in its class colour, then the skill. */
function Holders({ holders }: { holders: readonly Holder[] }) {
  return (
    <Stack gap={2}>
      {holders.map((h) => (
        <Text key={h.name} size="sm" c="dimmed">
          <CharacterName name={h.name} classFile={h.classFile} /> {h.rank}/{h.maxRank}
        </Text>
      ))}
    </Stack>
  )
}

/** The cards answering `step`, the current answer marked. */
function StepCards({
  step,
  setup,
  professions,
  unavailable,
  onPick,
}: {
  step: Step
  setup: SetupAnswers | null
  professions: readonly ProfessionChoice[]
  unavailable: Partial<Record<Aim, string>>
  onPick: (value: string) => void
}) {
  const current: string | undefined = setup?.[step]
  const options: { card: Card<string>; icon?: ReactNode; body?: ReactNode; reason?: string }[] =
    step === 'aim'
      ? AIMS.map((card) => ({ card, icon: AIM_ICONS[card.key], reason: unavailable[card.key] }))
      : step === 'selling'
        ? SELLING.map((card) => ({ card }))
        : professions.length === 0
          ? []
          : [
              { card: ANY_CARD },
              ...professions.map((p) => ({
                card: { key: p.name, title: p.name, blurb: '' },
                body: <Holders holders={p.holders} />,
              })),
            ]
  if (!options.length) {
    return (
      <Text size="sm" c="dimmed">
        None of your characters on this realm has a profession yet. Pick another realm, or make gold instead.
      </Text>
    )
  }
  return (
    <div className={classes.cards} role="group" aria-label={STEP_QUESTION[step]}>
      {options.map(({ card, icon, body, reason }) => (
        <OptionCard
          key={card.key}
          card={card}
          icon={icon}
          body={body}
          picked={card.key === current}
          reason={reason}
          onPick={() => onPick(card.key)}
        />
      ))}
    </div>
  )
}

/**
 * The questions before the search, one at a time while `step` is set (the answers so far above it, each a way back to
 * its question), else one line of the answers, each opening its question again. `children` shows under the question:
 * the realm picker, when the question depends on the realm.
 */
export function Setup({
  setup,
  step,
  professions,
  unavailable = {},
  onPick,
  onOpen,
  children,
}: {
  setup: SetupAnswers | null
  step: Step | null
  professions: readonly ProfessionChoice[]
  unavailable?: Partial<Record<Aim, string>>
  onPick: (step: Step, value: string) => void
  onOpen: (step: Step) => void
  children?: ReactNode
}) {
  return (
    <AnimatePresence mode="wait" initial={false}>
      {step !== null || setup === null ? (
        <motion.div key={`step-${step ?? 'aim'}`} {...FADE} transition={{ duration: 0.2 }}>
          <Stack gap="sm">
            {setup && step !== 'aim' && <Answers setup={setup} skip={step ?? undefined} onOpen={onOpen} />}
            <Title order={3}>{STEP_QUESTION[step ?? 'aim']}</Title>
            {children}
            <StepCards
              step={step ?? 'aim'}
              setup={setup}
              professions={professions}
              unavailable={unavailable}
              onPick={(value) => onPick(step ?? 'aim', value)}
            />
          </Stack>
        </motion.div>
      ) : (
        <motion.div key="setup-strip" className={cards.strip} {...FADE} transition={{ duration: 0.2 }}>
          <Group gap="sm" wrap="nowrap" role="group" aria-label="Your setup">
            <span className={cards.icon} data-small>
              {AIM_ICONS[setup.aim]}
            </span>
            <Answers setup={setup} onOpen={onOpen} />
          </Group>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
