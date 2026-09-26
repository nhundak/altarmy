import { useEffect, useMemo, useRef, type ReactNode } from 'react'
import { Alert, Center, Loader } from '@mantine/core'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useConfig, useMe } from '../api/queries'
import { initAuth, onUserChange } from '../lib/auth'
import { SessionContext, type Session } from '../lib/session'

const AUTH_KEYS = new Set(['config', 'sign-in', 'me'])

/**
 * Signs the visitor in before rendering the app: an anonymous Firebase sign-in, or the stored session
 * (against the Auth emulator in development). Then provides who they are (`useSession`).
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
  })
  const me = useMe(signIn.data === true)
  const queryClient = useQueryClient()
  // Signing in, linking or signing out changes the token: ask the API who that is now.
  useEffect(() => onUserChange(() => void queryClient.invalidateQueries({ queryKey: ['me'] })), [queryClient])
  const session = useMemo<Session | undefined>(
    () => (me.data ? { uid: me.data.uid, tier: me.data.tier } : undefined),
    [me.data],
  )
  useRefetchOnUserChange(session)

  const error = config.error ?? signIn.error ?? me.error
  if (error) {
    return (
      <Alert color="red" title="Could not sign in" m="md">
        {error.message}
      </Alert>
    )
  }
  if (!session) {
    return (
      <Center h="50vh">
        <Loader aria-label="Signing in" />
      </Center>
    )
  }
  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>
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
