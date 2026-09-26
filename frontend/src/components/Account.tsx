import { useState } from 'react'
import { Alert, Anchor, Button, Group, Menu, Modal, PasswordInput, SegmentedControl, Stack, Text, TextInput } from '@mantine/core'
import { notifications } from '@mantine/notifications'
import { useQueryClient } from '@tanstack/react-query'
import { authErrorMessage, currentEmail, linkWithEmail, resetPassword, signInWithEmail, signOut } from '../lib/auth'
import { useSession } from '../lib/session'

type Mode = 'sign-in' | 'create'

const MODES: { value: Mode; label: string }[] = [
  { value: 'sign-in', label: 'Sign in' },
  { value: 'create', label: 'Create account' },
]

const EXPLAIN: Readonly<Record<Mode, string>> = {
  'sign-in': "Signing in switches to that account's characters and settings.",
  create: 'Creating an account keeps the characters and settings already in this browser, and brings them to any other.',
}

/**
 * Sign in to an account made before, e.g. on another computer, or create one from this browser's session (same uid,
 * so its data stays).
 */
function AccountModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const queryClient = useQueryClient()
  const [mode, setMode] = useState<Mode>('sign-in')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const run = async (action: () => Promise<void>, done: () => void) => {
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      await action()
      done()
    } catch (e) {
      setError(authErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  const submit = () =>
    run(
      () => (mode === 'create' ? linkWithEmail(email.trim(), password) : signInWithEmail(email.trim(), password)),
      () => {
        void queryClient.invalidateQueries({ queryKey: ['me'] })
        notifications.show({
          color: 'green',
          title: mode === 'create' ? 'Account created' : 'Signed in',
          message: mode === 'create' ? `Signed in as ${email.trim()}.` : `Welcome back, ${email.trim()}.`,
        })
        onClose()
      },
    )

  const forgot = () =>
    run(
      () => resetPassword(email.trim()),
      () => setNotice(`If ${email.trim()} has an account, a link to set a new password is on its way.`),
    )

  const label = mode === 'create' ? 'Create account' : 'Sign in'
  return (
    <Modal opened={opened} onClose={onClose} title="Your account">
      <form
        onSubmit={(e) => {
          e.preventDefault()
          void submit()
        }}
      >
        <Stack gap="sm">
          <SegmentedControl
            fullWidth
            aria-label="Sign in or create an account"
            data={MODES}
            value={mode}
            onChange={(v) => {
              setMode(v === 'create' ? 'create' : 'sign-in')
              setError(null)
              setNotice(null)
            }}
          />
          <Text size="sm" c="dimmed">
            {EXPLAIN[mode]}
          </Text>
          {error && <Alert color="red">{error}</Alert>}
          {notice && <Alert color="green">{notice}</Alert>}
          <TextInput label="Email" type="email" value={email} onChange={(e) => setEmail(e.currentTarget.value)} required />
          <PasswordInput label="Password" value={password} onChange={(e) => setPassword(e.currentTarget.value)} required />
          <Group justify="space-between">
            {mode === 'sign-in' ? (
              <Anchor component="button" type="button" size="sm" onClick={() => void forgot()} disabled={busy}>
                Forgot password?
              </Anchor>
            ) : (
              <span />
            )}
            <Button type="submit" loading={busy}>
              {label}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  )
}

/** The header's "Sign in", which also offers creating an account. */
function SignInButton() {
  const [open, setOpen] = useState(false)
  return (
    <>
      <Button variant="default" onClick={() => setOpen(true)}>
        Sign in
      </Button>
      {/* Remounted on each open, so it starts empty. */}
      {open && <AccountModal opened onClose={() => setOpen(false)} />}
    </>
  )
}

/** The signed-in email, with signing out in its menu. */
function AccountMenu() {
  const [busy, setBusy] = useState(false)
  const out = async () => {
    setBusy(true)
    try {
      await signOut()
    } catch (e) {
      notifications.show({ color: 'red', title: 'Could not sign out', message: authErrorMessage(e) })
    } finally {
      setBusy(false)
    }
  }
  return (
    <Menu position="bottom-end" withinPortal>
      <Menu.Target>
        <Button variant="default" loading={busy} maw={240}>
          <Text span size="sm" truncate>
            {currentEmail() ?? 'Your account'}
          </Text>
        </Button>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Item onClick={() => void out()}>Sign out</Menu.Item>
      </Menu.Dropdown>
    </Menu>
  )
}

/** Hosted mode's header: the account menu once signed in, else the way in. */
export function AccountControls() {
  const { tier } = useSession()
  return tier === 'linked' ? <AccountMenu /> : <SignInButton />
}
