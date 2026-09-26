import { screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Config, Me } from '../api/client'
import { initAuth } from '../lib/auth'
import { useSession } from '../lib/session'
import { mockApi, renderWithProviders } from '../test/utils'
import { AuthProvider } from './AuthProvider'

// The Firebase SDK is never loaded in tests: sign-in is a stub, and the token a fixed string.
vi.mock('../lib/auth', () => ({
  initAuth: vi.fn(async () => {}),
  getIdToken: vi.fn(async () => 'id-token'),
  onUserChange: vi.fn(() => () => {}),
}))

const firebase = {
  api_key: 'key',
  auth_domain: 'demo-altarmy.firebaseapp.com',
  project_id: 'demo-altarmy',
  emulator_url: 'http://127.0.0.1:9099',
}
const config: Config = { firebase }
const guest: Me = { uid: 'guest', tier: 'free' }

function Who() {
  const s = useSession()
  return <p>{`${s.uid} ${s.tier}`}</p>
}

const renderApp = () =>
  renderWithProviders(
    <AuthProvider>
      <Who />
    </AuthProvider>,
  )

describe('AuthProvider', () => {
  afterEach(() => vi.clearAllMocks())

  it('signs in with Firebase, then asks the API who that is', async () => {
    const fetch = mockApi({ '/api/config': config, '/api/me': guest })
    renderApp()
    expect(await screen.findByText('guest free')).toBeInTheDocument()
    expect(initAuth).toHaveBeenCalledWith(firebase)
    const me = fetch.mock.calls.map(([r]) => r).find((r) => new URL(r.url).pathname === '/api/me')
    expect(me?.headers.get('Authorization')).toBe('Bearer id-token')
  })

  it('explains a failed sign-in', async () => {
    vi.mocked(initAuth).mockRejectedValueOnce(new Error('auth/network-request-failed'))
    mockApi({ '/api/config': config, '/api/me': guest })
    renderApp()
    expect(await screen.findByText('auth/network-request-failed')).toBeInTheDocument()
  })
})
