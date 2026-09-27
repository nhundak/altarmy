import type { ReactNode } from 'react'
import { Button, Group, Stack, Text, Title, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion } from 'motion/react'
import { GOALS, type Goal } from '../lib/goals'
import cards from './Cards.module.css'
import classes from './GoalPicker.module.css'
import { IconClock, IconCoin, IconSteps } from './icons'

const ICONS: Readonly<Record<Goal, ReactNode>> = {
  profit: <IconClock />,
  budget: <IconCoin />,
  skill: <IconSteps />,
}

const FADE = { initial: { opacity: 0, y: -8 }, animate: { opacity: 1, y: 0 }, exit: { opacity: 0, y: -8 } }

/**
 * "What is your goal?": three cards while `choosing`, else one line naming the chosen goal with a way back to the
 * cards. The goal sets how the search below ranks.
 */
export function GoalPicker({
  goal,
  choosing,
  onPick,
  onChange,
}: {
  goal: Goal | null
  choosing: boolean
  onPick: (goal: Goal) => void
  onChange: () => void
}) {
  const chosen = GOALS.find((g) => g.key === goal)
  return (
    <AnimatePresence mode="wait" initial={false}>
      {choosing || !chosen ? (
        <motion.div key="goal-cards" {...FADE} transition={{ duration: 0.2 }}>
          <Stack gap="sm">
            <Title order={3}>What is your goal?</Title>
            <div className={classes.goals} role="group" aria-label="Your goal">
              {GOALS.map((g) => (
                <div key={g.key} className={cards.card} data-featured={g.key === goal || undefined}>
                  <UnstyledButton
                    className={cards.pick}
                    onClick={() => onPick(g.key)}
                    aria-label={g.title}
                    aria-pressed={g.key === goal}
                  >
                    <Stack gap="sm">
                      <span className={cards.icon}>{ICONS[g.key]}</span>
                      <Title order={4}>{g.title}</Title>
                      <Text size="sm" c="dimmed">
                        {g.blurb}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {g.details}
                      </Text>
                    </Stack>
                  </UnstyledButton>
                </div>
              ))}
            </div>
          </Stack>
        </motion.div>
      ) : (
        <motion.div key="goal-strip" className={cards.strip} {...FADE} transition={{ duration: 0.2 }}>
          <Group justify="space-between" gap="sm" wrap="nowrap">
            <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
              <span className={cards.icon} data-small>
                {ICONS[chosen.key]}
              </span>
              <Text size="sm">
                <b>Goal: {chosen.title}.</b>{' '}
                <Text span c="dimmed" size="sm">
                  {chosen.blurb}
                </Text>
              </Text>
            </Group>
            <Button size="xs" variant="light" onClick={onChange} style={{ flex: 'none' }}>
              Change goal
            </Button>
          </Group>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
