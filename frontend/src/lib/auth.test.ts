import { beforeEach, describe, expect, it, vi } from 'vitest'

/** A fake Firebase Auth: `currentUser` is whoever is signed in; signing in anonymously makes a new user. */
type FakeUser = { uid: string; getIdToken: () => Promise<string> }
const fake = vi.hoisted(() => ({
  auth: { currentUser: null as FakeUser | null, authStateReady: async () => {} },
  tokenListener: null as ((user: FakeUser | null) => void) | null,
  anonymous: 0,
}))

vi.mock('firebase/app', () => ({ initializeApp: vi.fn(() => ({})), getApps: vi.fn(() => []) }))
vi.mock('firebase/auth', () => ({
  getAuth: vi.fn(() => fake.auth),
  connectAuthEmulator: vi.fn(),
  signInAnonymously: vi.fn(async () => {
    fake.anonymous += 1
    const uid = `anon-${fake.anonymous}`
    fake.auth.currentUser = { uid, getIdToken: async () => `token-${uid}` }
    fake.tokenListener?.(fake.auth.currentUser)
  }),
  onIdTokenChanged: vi.fn((_auth: unknown, listener: (user: FakeUser | null) => void) => {
    fake.tokenListener = listener
  }),
  signOut: vi.fn(async () => {
    fake.auth.currentUser = null
    fake.tokenListener?.(null)
  }),
}))

const config = { api_key: 'key', auth_domain: 'demo.firebaseapp.com', project_id: 'demo', emulator_url: null }

async function freshAuth() {
  vi.resetModules()
  return import('./auth')
}

describe('auth', () => {
  beforeEach(() => {
    fake.auth.currentUser = null
    fake.tokenListener = null
    fake.anonymous = 0
  })

  it('signs in anonymously when no session is stored', async () => {
    const auth = await freshAuth()
    await auth.initAuth(config)
    expect(await auth.getIdToken()).toBe('token-anon-1')
  })

  it('retries the sign-in when the sign-in server was unreachable', async () => {
    const fa = await import('firebase/auth')
    vi.mocked(fa.signInAnonymously).mockRejectedValueOnce(new Error('auth/network-request-failed'))
    const auth = await freshAuth()
    await expect(auth.initAuth(config)).rejects.toThrow('auth/network-request-failed')
    await auth.initAuth(config)
    expect(await auth.getIdToken()).toBe('token-anon-1')
  })

  it('replaces a stored session Firebase can no longer refresh with a new anonymous one', async () => {
    // The stored user is gone (deleted, or the emulator restarted): refreshing fails and Firebase signs it out.
    fake.auth.currentUser = {
      uid: 'stale',
      getIdToken: async () => {
        fake.auth.currentUser = null
        throw new Error('auth/user-token-expired')
      },
    }
    const auth = await freshAuth()
    await auth.initAuth(config)
    expect(await auth.getIdToken()).toBe('token-anon-1')
  })

  it('signs in again when Firebase drops the session on its own', async () => {
    const auth = await freshAuth()
    await auth.initAuth(config)
    fake.auth.currentUser = null
    fake.tokenListener?.(null)
    expect(await auth.getIdToken()).toBe('token-anon-2')
  })

  it('never sends a request without a user after signing out', async () => {
    const auth = await freshAuth()
    await auth.initAuth(config)
    await auth.signOut()
    expect(await auth.getIdToken()).toBe('token-anon-2')
    expect(fake.anonymous).toBe(2)
  })
})
