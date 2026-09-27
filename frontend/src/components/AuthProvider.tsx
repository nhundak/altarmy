import { useEffect, useMemo, useRef, type ReactNode } from 'react'
import { Alert, Center, Loader } from '@mantine/core'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { KEEP_TRYING, useConfig, useMe } from '../api/queries'
import { authErrorMessage, initAuth, onUserChange } from '../lib/auth'
import { SessionContext, SIGNED_OUT, type Session } from '../lib/session'

const AUTH_KEYS = new Set(['config', 'sign-in', 'me'])

/**
 * Signs the visitor in before rendering the app: an anonymous Firebase sign-in, or the stored session
 * (against the Auth emulator in development). Then provides who they are (`useSession`). If signing in fails, the
 * app shows signed out (`SIGNED_OUT`) under a notice, and signing in is retried until it works.
 */
export function AuthProvider({ children }: { children: ReactNode }) {
  const config = useConfig()
  const firebase = config.data?.firebase
  const signIn = useQuery({
    queryKey: ['sign-in'],
    queryFn: async () => {
      await initAuth(firebase!)
      return true
    },
    enabled: firebase !== undefined,
    staleTime: Infinity,
    ...KEEP_TRYING,
  })
  const me = useMe(signIn.data === true)
  const queryClient = useQueryClient()
  // Signing in, linking or signing out changes the token: ask the API who that is now.
  useEffect(() => onUserChange(() => void queryClient.invalidateQueries({ queryKey: ['me'] })), [queryClient])
  const signedIn = useMemo<Session | undefined>(
    () => (me.data ? { uid: me.data.uid, tier: me.data.tier } : undefined),
    [me.data],
  )

  // Once signed in, keep the app up if a later refetch of who they are fails: its data is still the session.
  // Before that, a failure (the sign-in server unreachable) shows the app signed out while signing in is retried.
  const problem = signedIn ? null : (config.failureReason ?? signIn.failureReason ?? me.error)
  const session = signedIn ?? (problem ? SIGNED_OUT : undefined)
  useRefetchOnUserChange(session)

  if (!session) {
    return (
      <Center h="50vh">
        <Loader aria-label="Signing in" />
      </Center>
    )
  }
  return (
    <SessionContext.Provider value={session}>
      {problem && (
        <Alert color="yellow" title="Could not sign in" m="md">
          {authErrorMessage(problem)} Your data will show once signing in works; trying again.
        </Alert>
      )}
      {children}
    </SessionContext.Provider>
  )
}

/** A different user or tier (after linking) sees different data: refetch everything but the sign-in itself. */
function useRefetchOnUserChange(session: Session | undefined) {
  const queryClient = useQueryClient()
  const who = session && `${session.uid}:${session.tier}`
  const last = useRef(who)
  useEffect(() => {
    if (last.current !== undefined && who !== last.current) {
      void queryClient.invalidateQueries({ predicate: (q) => !AUTH_KEYS.has(String(q.queryKey[0])) })
    }
    last.current = who
  }, [who, queryClient])
}
