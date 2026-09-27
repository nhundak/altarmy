import { Alert, Anchor, Card, Code, Stack, Text, Title } from '@mantine/core'
import { useSession } from '../lib/session'

/** The newest Alt Army Sync build (.github/workflows/sync.yml publishes it on a sync-v* tag). */
export const SYNC_DOWNLOAD = 'https://github.com/ntower/altarmy-profit/releases/latest/download/altarmy-sync.exe'

/** The Manage page's pointer to Alt Army Sync (and the CLI watcher), which sign in with the account's email. */
export function SyncCard() {
  const { tier } = useSession()
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={3}>Upload automatically</Title>
        <Text size="sm" c="dimmed">
          The{' '}
          <Anchor href={SYNC_DOWNLOAD} size="sm">
            Alt Army Sync for Windows
          </Anchor>{' '}
          (or <Code>altarmy-profit watch</Code> from the Python package) runs on the computer you play on and uploads
          AltArmy_TBC.lua and Auctionator.lua whenever WoW rewrites them. It signs in with your account's email and
          password once and keeps only a sign-in token, never the password; signing out in its menu forgets it.
          Windows warns once because the app is unsigned (More info → Run anyway).
        </Text>
        {tier === 'free' && (
          <Alert color="blue">
            The app signs in to an account: create one with Sign in (top right) to keep what you have set up in this
            browser, or create one in the app.
          </Alert>
        )}
      </Stack>
    </Card>
  )
}
