import type { Auth, User } from 'firebase/auth'
import type { components } from '../api/schema'

/**
 * Firebase sign-in. The Firebase SDK is loaded on first use, so it stays out of the main bundle.
 *
 * Every visitor is signed in anonymously. Linking an email and password keeps the uid (and with it the user's data)
 * and moves them to the linked tier; on another browser they sign in with that email. Signing out starts a new
 * anonymous session.
 */
export type FirebaseConfig = components['schemas']['FirebaseOut']

let auth: Auth | null = null
let started: Promise<void> | null = null
let signingIn: Promise<void> | null = null
const listeners = new Set<() => void>()

/** Start Firebase and sign in anonymously unless a session is already stored. Safe to call twice. */
export function initAuth(config: FirebaseConfig): Promise<void> {
  started ??= (async () => {
    const [{ initializeApp }, fa] = await Promise.all([import('firebase/app'), import('firebase/auth')])
    const app = initializeApp({ apiKey: config.api_key, authDomain: config.auth_domain, projectId: config.project_id })
    const a = fa.getAuth(app)
    if (config.emulator_url) fa.connectAuthEmulator(a, config.emulator_url, { disableWarnings: true })
    await a.authStateReady()
    auth = a
    await ensureUser()
    fa.onIdTokenChanged(a, (user) => {
      // Firebase drops a stored session it can no longer refresh (the account was deleted, or the emulator
      // restarted): start a new anonymous one, whose sign-in notifies the listeners in turn.
      if (user) listeners.forEach((l) => l())
      else void ensureUser().catch(() => {})
    })
  })()
  return started
}

/** Sign in anonymously unless someone is signed in; concurrent callers share one sign-in. */
async function ensureUser(): Promise<void> {
  const a = auth
  if (!a || a.currentUser) return
  signingIn ??= import('firebase/auth')
    .then((fa) => fa.signInAnonymously(a))
    .then(() => {})
    .finally(() => {
      signingIn = null
    })
  return signingIn
}

/** Call `listener` whenever the signed-in user or their token changes (sign-in, linking, sign-out). */
export function onUserChange(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/**
 * The signed-in user's ID token for the API, or null before sign-in. Firebase refreshes it when it expires; if the
 * stored session can no longer be refreshed, a new anonymous one takes its place.
 */
export async function getIdToken(): Promise<string | null> {
  const a = auth
  if (!a) return null
  // A function, not `a.currentUser?.getIdToken()` twice: TypeScript would keep its narrowing across the sign-in.
  const token = async () => {
    await ensureUser()
    return (await a.currentUser?.getIdToken()) ?? null
  }
  try {
    return await token()
  } catch (error) {
    if (a.currentUser) throw error // a network failure, not a lost session
    return token()
  }
}

/** The signed-in account's email, if it has one (linked accounts). */
export function currentEmail(): string | null {
  return auth?.currentUser?.email ?? null
}

function requireAuth(): Auth {
  if (!auth) throw new Error('Sign-in has not started.')
  return auth
}

function currentUser(): User {
  const user = requireAuth().currentUser
  if (!user) throw new Error('Not signed in.')
  return user
}

/** Create an account from this browser's anonymous session: same uid (and data), now the linked tier. */
export async function linkWithEmail(email: string, password: string): Promise<void> {
  const fa = await import('firebase/auth')
  const user = currentUser()
  await fa.linkWithCredential(user, fa.EmailAuthProvider.credential(email, password))
  await user.getIdToken(true) // the new token says "password", which the API reads as linked
}

/** Sign in to an existing account; the anonymous session's data stays with its uid. */
export async function signInWithEmail(email: string, password: string): Promise<void> {
  const fa = await import('firebase/auth')
  await fa.signInWithEmailAndPassword(requireAuth(), email, password)
}

/** Email a link to set a new password. */
export async function resetPassword(email: string): Promise<void> {
  const fa = await import('firebase/auth')
  await fa.sendPasswordResetEmail(requireAuth(), email)
}

/** Sign out, into a fresh anonymous session. */
export async function signOut(): Promise<void> {
  const fa = await import('firebase/auth')
  const a = requireAuth()
  await fa.signOut(a)
  await ensureUser()
}

const AUTH_ERRORS: Readonly<Record<string, string>> = {
  'auth/credential-already-in-use': 'That email already has an account: sign in instead.',
  'auth/email-already-in-use': 'That email already has an account: sign in instead.',
  'auth/invalid-credential': 'Wrong email or password.',
  'auth/wrong-password': 'Wrong email or password.',
  'auth/user-not-found': 'Wrong email or password.',
  'auth/too-many-requests': 'Too many attempts. Wait a few minutes, or reset your password.',
  'auth/weak-password': 'Pick a password of at least 6 characters.',
  'auth/invalid-email': 'That is not a valid email address.',
  'auth/missing-email': 'Enter your email address first.',
}

/** What to tell the user when signing in, linking or resetting failed. */
export function authErrorMessage(error: unknown): string {
  const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : ''
  return AUTH_ERRORS[code] ?? (error instanceof Error ? error.message : 'Something went wrong.')
}
