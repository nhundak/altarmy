import { createContext, useContext } from 'react'
import type { components } from '../api/schema'

/** free: an anonymous guest (everything the site has); linked: signed in with an email address. */
export type Tier = components['schemas']['Me']['tier']

/** `uid` is null while nobody is signed in (signing in failed, and is being retried). */
export type Session = { uid: string | null; tier: Tier }

/** What components see outside an AuthProvider, as in most tests: a signed-in user with an account. */
export const FALLBACK_SESSION: Session = { uid: 'g1', tier: 'linked' }

/** Nobody is signed in: the app still shows, like to a guest, and requests sign in when they can. */
export const SIGNED_OUT: Session = { uid: null, tier: 'free' }

export const SessionContext = createContext<Session>(FALLBACK_SESSION)

/** Who is signed in, and what the app may show them. */
export const useSession = () => useContext(SessionContext)
