import type { ReactNode } from 'react'
import { Alert, Anchor, Button, Code, Group, List, SimpleGrid, Stack, Text, Title } from '@mantine/core'
import { linkProps } from '../lib/router'
import { useSession } from '../lib/session'
import { motion } from 'motion/react'
import { AdminTab } from './AdminTab'
import cards from './Cards.module.css'
import { IconDownload, IconExternal } from './icons'
import { ADDON_SHOWCASE, ShowcaseCard } from './Landing'
import { ManageTab } from './ManageTab'

function Page({ title, lead, children }: { title: string; lead?: ReactNode; children: ReactNode }) {
  return (
    <Stack gap="lg">
      <Stack gap={4}>
        <Anchor size="sm" {...linkProps('/profit')}>
          ← Back to the search
        </Anchor>
        <Title order={2}>{title}</Title>
        {lead && (
          <Text c="dimmed" maw="70ch">
            {lead}
          </Text>
        )}
      </Stack>
      {children}
    </Stack>
  )
}

export const CURSEFORGE_URL = 'https://www.curseforge.com/wow/addons/alt-army'
export const WAGO_URL = 'https://addons.wago.io/addons/aNDMjY6o'
/**
 * The newest stable addon zip: .github/workflows/addon-release.yml attaches it to a GitHub Release on each
 * addon-v* tag, and only addon releases become the repository's Latest.
 */
export const ADDON_ZIP = 'https://github.com/ntower/altarmy/releases/latest/download/AltArmy_TBC.zip'

type Source = { title: string; copy: ReactNode; href: string; action: string; external?: boolean }

const SOURCES: readonly Source[] = [
  {
    title: 'CurseForge',
    copy: 'Install it with the CurseForge app, which keeps it up to date.',
    href: CURSEFORGE_URL,
    action: 'Open on CurseForge',
    external: true,
  },
  {
    title: 'Wago',
    copy: 'Install it with the Wago app (or WowUp), which keeps it up to date.',
    href: WAGO_URL,
    action: 'Open on Wago',
    external: true,
  },
  {
    title: 'Download the zip',
    copy: (
      <>
        Unzip it into <Code>_classic_beta_\Interface\AddOns</Code> (Forever) or{' '}
        <Code>_anniversary_\Interface\AddOns</Code> (Burning Crusade) in your WoW folder. Updates are by hand.
      </>
    ),
    href: ADDON_ZIP,
    action: 'Download AltArmy_TBC.zip',
  },
]

function SourceCard({ source }: { source: Source }) {
  const titleId = `addon-source-${source.title.toLowerCase().replaceAll(' ', '-')}`
  return (
    <article className={cards.card} aria-labelledby={titleId}>
      <Stack gap="sm" p="lg" h="100%">
        <Group gap="sm" wrap="nowrap">
          <span className={cards.icon} aria-hidden="true">
            {source.external ? <IconExternal /> : <IconDownload />}
          </span>
          <Title order={3} size="h4" id={titleId}>
            {source.title}
          </Title>
        </Group>
        <Text size="sm" c="dimmed" style={{ flex: 1 }}>
          {source.copy}
        </Text>
        <Group>
          <Button
            component="a"
            href={source.href}
            variant={source.external ? 'light' : 'filled'}
            {...(source.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
          >
            {source.action}
          </Button>
        </Group>
      </Stack>
    </article>
  )
}

/**
 * The addon's showcase card as a "Get the Addon" banner (carried over from the main page's card), then where to get it: CurseForge, Wago, or the zip
 * itself; then what to do with it. The rest comes in under the card, which may already be on screen.
 */
export function AddonPage() {
  return (
    <Stack gap="lg">
      <ShowcaseCard spec={ADDON_SHOWCASE} home />
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.35, delay: 0.1, ease: [0.25, 0.8, 0.25, 1] }}
      >
        <Stack gap="lg">
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="md">
            {SOURCES.map((source) => (
              <SourceCard key={source.title} source={source} />
            ))}
          </SimpleGrid>
          <Stack gap="sm" maw="70ch">
            <Text>Once it is installed:</Text>
            <List spacing={4}>
              <List.Item>Log into each of your characters once and open their professions.</List.Item>
              <List.Item>
                Type <Code>/altarmy export</Code> in game and press Ctrl+C.
              </List.Item>
              <List.Item>Paste the export into Upload your characters on the Profit page.</List.Item>
            </List>
            <Text>For auction house prices:</Text>
            <List spacing={4}>
              <List.Item>
                At the auction house, press <b>Alt Army scan</b> and keep the window open until it finishes. The game
                allows one full scan every 15 minutes.
              </List.Item>
              <List.Item>
                Log out or type <Code>/reload</Code>, then upload AltArmy_TBC.lua with Upload your scan under
                Realm on the <Anchor {...linkProps('/profit')}>Profit page</Anchor>, or let Alt Army Sync send it.
              </List.Item>
            </List>
          </Stack>
        </Stack>
      </motion.div>
    </Stack>
  )
}

/** Site admins only (the Firebase `admin` claim); anyone else who opens it gets a notice, and no request. */
export function AdminPage() {
  const { admin } = useSession()
  return (
    <Page title="Admin" lead="What the scheduled jobs and uploads have been doing.">
      {admin ? <AdminTab /> : <Alert color="yellow">This page is for site admins. Sign in with an admin account.</Alert>}
    </Page>
  )
}

export function ManagePage() {
  return (
    <Page title="Manage">
      <ManageTab />
    </Page>
  )
}
