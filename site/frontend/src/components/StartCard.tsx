import type { ReactNode } from 'react'
import { Badge, CloseButton, Group, Stack, Text, Title, UnstyledButton } from '@mantine/core'
import { motion } from 'motion/react'
import { LAYOUT } from '../lib/motion'
import cards from './Cards.module.css'

/** How a row of start cards is laid out: side by side, one open on the left with the rest beside it, or folded away. */
export type Phase = 'choose' | 'expanded' | 'collapsed'

export type CardSpec<K extends string = string> = {
  key: K
  title: string
  blurb: string
  short: string
  icon: ReactNode
  /** featured, with a Recommended badge while the cards are side by side */
  recommended?: boolean
}

/** An open card's heading: its icon and title, and the button that closes it. */
export function OpenCardHeader({ spec, onClose, closeLabel }: { spec: CardSpec; onClose: () => void; closeLabel: string }) {
  return (
    <Group justify="space-between" align="flex-start" wrap="nowrap" mb="md">
      <Group gap="sm" wrap="nowrap">
        <span className={cards.icon}>{spec.icon}</span>
        <Title order={3}>{spec.title}</Title>
      </Group>
      <CloseButton aria-label={closeLabel} onClick={onClose} />
    </Group>
  )
}

/** An open card's content, fading in once the card has moved into place. */
export function OpenCardBody({ children }: { children: ReactNode }) {
  return (
    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25, delay: 0.1 }}>
      {children}
    </motion.div>
  )
}

/** One of several ways to go on: a big button while choosing, its steps once opened, a small button beside it. */
export function StartCard({
  spec,
  phase,
  open,
  onPick,
  onClose,
  closeLabel = 'Back to the three ways to start',
  layoutId,
  fade = false,
  children,
}: {
  spec: CardSpec
  phase: Phase
  open: boolean
  onPick: () => void
  onClose: () => void
  closeLabel?: string
  /** shared with another box (the Profit page's characters strip), so one resizes into the other */
  layoutId?: string
  /** fades in as it appears (a card beside the one growing out of the strip) */
  fade?: boolean
  children?: ReactNode
}) {
  const compact = phase === 'expanded' && !open
  return (
    <motion.div
      layout
      transition={LAYOUT}
      className={cards.slot}
      data-open={open || undefined}
      style={{ borderRadius: 12 }}
      {...(fade && { initial: { opacity: 0 }, animate: { opacity: 1 } })}
    >
      <motion.div
        layout
        layoutId={layoutId}
        transition={LAYOUT}
        className={cards.card}
        data-featured={(spec.recommended && !compact) || undefined}
        style={{ borderRadius: 12 }}
      >
        {open ? (
          <motion.div layout="position" className={cards.open}>
            <OpenCardHeader spec={spec} onClose={onClose} closeLabel={closeLabel} />
            <OpenCardBody>{children}</OpenCardBody>
          </motion.div>
        ) : (
          <UnstyledButton className={cards.pick} onClick={onPick} aria-label={spec.title}>
            <motion.div layout="position">
              {compact ? (
                <Group gap="sm" wrap="nowrap">
                  <span className={cards.icon} data-small>
                    {spec.icon}
                  </span>
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
                    <span className={cards.icon}>{spec.icon}</span>
                    {spec.recommended && (
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
