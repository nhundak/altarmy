import type { ReactNode } from 'react'
import { Anchor, Code, List, Stack, Text, Title } from '@mantine/core'
import { linkProps } from '../lib/router'
import { ManageTab } from './ManageTab'
import { UploadTab } from './UploadTab'

function Page({ title, lead, children }: { title: string; lead?: ReactNode; children: ReactNode }) {
  return (
    <Stack gap="lg">
      <Stack gap={4}>
        <Anchor size="sm" {...linkProps('/')}>
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

/** Where the addon will be downloaded; a placeholder until it is published. */
export function AddonPage() {
  return (
    <Page
      title="Get the Addon"
      lead="Alt Army is a WoW: Forever addon that remembers every one of your characters: their professions, skill and learned recipes."
    >
      <Stack gap="sm" maw="70ch">
        <Text fw={700}>The download is coming soon.</Text>
        <Text>Once it is installed:</Text>
        <List spacing={4}>
          <List.Item>Log in to each of your characters once, so Alt Army sees their professions.</List.Item>
          <List.Item>
            Type <Code>/altarmy export</Code> in game and press Ctrl+C.
          </List.Item>
          <List.Item>Paste the export into Import your characters on the main page.</List.Item>
        </List>
      </Stack>
    </Page>
  )
}

export function UploadPage() {
  return (
    <Page title="Upload" lead="Bring in characters and auction prices from WoW's saved files, and see which realms need a scan.">
      <UploadTab />
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
