import { createContext, useContext } from 'react'
import type { components } from '../api/schema'

/** free: an anonymous guest (everything the site has); linked: signed in with an email address. */
export type Tier = components['schemas']['Me']['tier']

export type Session = { uid: string; tier: Tier }

/** What components see outside an AuthProvider, as in most tests: a signed-in user with an account. */
export const FALLBACK_SESSION: Session = { uid: 'g1', tier: 'linked' }

export const SessionContext = createContext<Session>(FALLBACK_SESSION)

/** Who is signed in, and what the app may show them. */
export const useSession = () => useContext(SessionContext)
