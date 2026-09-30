import { useState, type ReactNode } from 'react'
import { Button, Group, Stack, Text, ThemeIcon, Title } from '@mantine/core'
import { currentEmail } from '../lib/auth'
import { useSession } from '../lib/session'
import { AccountModal } from './Account'
import { IconDownload } from './icons'
import { SYNC_DOWNLOAD } from './SyncCard'

/** One numbered step: its number (a tick once done), what to do, and the control that does it. */
function Step({ n, title, done, children }: { n: number; title: string; done?: boolean; children: ReactNode }) {
  return (
    <Group align="flex-start" wrap="nowrap" gap="sm" component="li">
      <ThemeIcon radius="xl" size={26} variant={done ? 'filled' : 'light'} aria-hidden>
        <Text size="xs" fw={700} span>
          {done ? '✓' : n}
        </Text>
      </ThemeIcon>
      <Stack gap={6} style={{ flex: 1, minWidth: 0 }}>
        <Title order={4} size="h5" pt={2}>
          {title}
        </Title>
        {children}
      </Stack>
    </Group>
  )
}

/**
 * The Auto-import start card: what Alt Army Sync does, then an account, the download and signing in to the app.
 * Once the app's first upload lands, the page's polling brings the characters in and the start cards fold away on
 * their own.
 */
export function AutoImportBody() {
  const { tier } = useSession()
  const [signingIn, setSigningIn] = useState(false)
  const linked = tier === 'linked'
  const email = linked ? currentEmail() : null
  return (
    <Stack gap="md">
      <Text size="sm">
        Addons can't reach the internet, so Alt Army writes what it sees to a file in your WoW folder.
        Alt Army Sync is a small Windows app that waits by the clock and sends those files here whenever the game
        saves them: when you log out, switch characters or reload. Your characters, their professions and recipes, and
        your latest auction scan stay current without pasting a thing.
      </Text>
      <Text size="sm" c="dimmed">
        It only reads AltArmy_TBC.lua and never changes a game file. It signs in to your account
        once and keeps only a sign-in token on your computer, never your password; Sign out in its menu forgets it.
      </Text>
      <Stack gap="lg" component="ol" m={0} p={0} style={{ listStyle: 'none' }}>
        <Step n={1} title="Create an account" done={linked}>
          {linked ? (
            <Text size="sm" c="dimmed">
              {email ? `Signed in as ${email}.` : 'Signed in.'}
            </Text>
          ) : (
            <>
              <Text size="sm" c="dimmed">
                The app uploads to your account. Making it here keeps what you have set up in this browser; the app can
                also make one, but that one starts empty.
              </Text>
              <Group>
                <Button size="sm" onClick={() => setSigningIn(true)}>
                  Sign in or create an account
                </Button>
              </Group>
              {/* Remounted on each open, so it starts empty. */}
              {signingIn && <AccountModal opened onClose={() => setSigningIn(false)} />}
            </>
          )}
        </Step>
        <Step n={2} title="Download and run Alt Army Sync">
          <Text size="sm" c="dimmed">
            Windows only. It finds your WoW folder on its own. It is not signed yet, so Windows warns you once: choose
            More info, then Run anyway.
          </Text>
          <Group>
            <Button component="a" href={SYNC_DOWNLOAD} variant="light" leftSection={<IconDownload size={18} />}>
              Download Alt Army Sync
            </Button>
          </Group>
        </Step>
        <Step n={3} title="Sign in to the app">
          <Text size="sm" c="dimmed">
            {email
              ? `It asks for your email and password the first time: use ${email} and the password you chose.`
              : 'It asks for your email and password the first time: use the account from step 1, or tick Create a new account there.'}
          </Text>
        </Step>
      </Stack>
      <Text size="sm" c="dimmed">
        Then log in to each of your characters once, with the Alt Army addon installed. Your characters show up here
        on their own after the first upload.
      </Text>
    </Stack>
  )
}
