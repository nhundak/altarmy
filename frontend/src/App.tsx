import { Container, Group, Tabs, Title } from '@mantine/core'
import { useAutoUpdateGameData, useSyncNotifications } from './api/queries'
import { AccountStatus, LinkPrompt } from './components/Account'
import { GameVersionProvider, GameVersionSwitch } from './components/GameVersionProvider'
import { ManageTab } from './components/ManageTab'
import { PrivacyNote } from './components/PrivacyNote'
import { SearchTab } from './components/SearchTab'
import { UploadTab } from './components/UploadTab'
import { useSession } from './lib/session'

export function App() {
  return (
    <GameVersionProvider>
      <Shell />
    </GameVersionProvider>
  )
}

/** Local mode keeps the game data current and toasts what the addon file sync imported. */
function LocalUpkeep() {
  useAutoUpdateGameData()
  useSyncNotifications()
  return null
}

function Shell() {
  const { mode, tier } = useSession()
  return (
    <Container size="xl" py="md">
      {mode === 'local' && <LocalUpkeep />}
      <Group justify="space-between" align="center" mb="md">
        <Title order={1}>altarmy-profit</Title>
        <Group>
          {mode === 'hosted' && <AccountStatus />}
          <GameVersionSwitch />
        </Group>
      </Group>
      {tier === 'free' && <LinkPrompt />}
      <Tabs defaultValue="search">
        <Tabs.List mb="md">
          <Tabs.Tab value="search">Search</Tabs.Tab>
          {mode === 'hosted' && <Tabs.Tab value="upload">Upload</Tabs.Tab>}
          <Tabs.Tab value="manage">Manage</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="search">
          <SearchTab />
        </Tabs.Panel>
        {mode === 'hosted' && (
          <Tabs.Panel value="upload">
            <UploadTab />
          </Tabs.Panel>
        )}
        <Tabs.Panel value="manage">
          <ManageTab />
        </Tabs.Panel>
      </Tabs>
      {mode === 'hosted' && <PrivacyNote />}
    </Container>
  )
}
