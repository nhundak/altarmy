import { useState } from 'react'
import { Alert, Button, Code, FileInput, Group, List, Stack } from '@mantine/core'
import { useUpload, type UploadKind } from '../api/queries'
import { GAME_VERSION_LABEL } from '../lib/gameVersion'
import { IconUpload } from './icons'
import { Summary } from './PasteForm'

const MAX_MB = 32

/** The Upload your scan button (the Realm card's and the Addon page's), which opens the upload. */
export function UploadScanButton({ onClick }: { onClick: () => void }) {
  return (
    <Button size="xs" variant="light" leftSection={<IconUpload size={16} />} onClick={onClick}>
      Upload your scan
    </Button>
  )
}

/** How to take a scan and bring it here, step by step (`upload`: the last step, where the file goes). */
export function ScanSteps({ upload }: { upload: string }) {
  return (
    <List size="sm" type="ordered">
      <List.Item>
        At the auction house, press <b>Alt Army scan</b> (or type <Code>/altarmy scan</Code>) and keep the window
        open until it finishes.
      </List.Item>
      <List.Item>
        Log out or type <Code>/reload</Code>, so WoW writes the scan to AltArmy_TBC.lua.
      </List.Item>
      <List.Item>{upload}</List.Item>
    </List>
  )
}

function uploadedTitle(realms: readonly { quarantined: boolean }[]): string {
  if (realms.some((r) => r.quarantined)) return 'Uploaded, but some prices were not used: they differ widely from recent scans'
  return 'Uploaded'
}

/** Pick an addon file and upload it, then say what it brought in (or why it was refused). */
export function UploadForm({ kind, name }: { kind: UploadKind; name: string }) {
  const upload = useUpload()
  const [file, setFile] = useState<File | null>(null)
  const tooBig = file !== null && file.size > MAX_MB * 2 ** 20
  return (
    <Stack gap="sm">
      <Group align="flex-end">
        <FileInput
          label={`${name} for ${GAME_VERSION_LABEL}`}
          placeholder={`Pick ${name}`}
          accept=".lua"
          value={file}
          onChange={(f) => {
            setFile(f)
            upload.reset()
          }}
          clearable
          w={360}
          maw="100%"
        />
        <Button disabled={!file || tooBig} loading={upload.isPending} onClick={() => file && upload.mutate({ kind, file })}>
          Upload
        </Button>
      </Group>
      {tooBig && <Alert color="red">Files are limited to {MAX_MB} MB.</Alert>}
      {upload.isError && <Alert color="red">{upload.error.message}</Alert>}
      {upload.data && (
        <Alert
          color={upload.data.realms.some((r) => r.quarantined) ? 'yellow' : 'green'}
          title={uploadedTitle(upload.data.realms)}
        >
          <Summary result={upload.data} />
        </Alert>
      )}
    </Stack>
  )
}
