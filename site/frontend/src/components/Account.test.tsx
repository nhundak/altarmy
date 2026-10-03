import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { linkWithEmail, resetPassword, signInWithEmail, signOut } from '../lib/auth'
import { GUEST, LINKED, mockApi, renderWithProviders } from '../test/utils'
import { AccountControls } from './Account'

vi.mock('../lib/auth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/auth')>()),
  getIdToken: vi.fn(async () => null),
  currentEmail: vi.fn(() => 'me@example.com'),
  linkWithEmail: vi.fn(async () => {}),
  signInWithEmail: vi.fn(async () => {}),
  resetPassword: vi.fn(async () => {}),
  signOut: vi.fn(async () => {}),
}))

async function fill(email: string, password = '') {
  await userEvent.type(await screen.findByLabelText(/Email/), email)
  if (password) await userEvent.type(screen.getByLabelText(/Password/), password)
}

const submit = (name: string) => userEvent.click(screen.getAllByRole('button', { name }).at(-1)!)

describe('account', () => {
  afterEach(() => vi.clearAllMocks())

  it('creates an account that keeps this browser’s data', async () => {
    mockApi({})
    renderWithProviders(<AccountControls />, GUEST)
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/Google/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await userEvent.click(await screen.findByText('Create account'))
    await fill('me@example.com', 'hunter22')
    await submit('Create account')
    await waitFor(() => expect(linkWithEmail).toHaveBeenCalledWith('me@example.com', 'hunter22'))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  })

  it('points a taken email to signing in', async () => {
    vi.mocked(linkWithEmail).mockRejectedValueOnce(Object.assign(new Error('x'), { code: 'auth/email-already-in-use' }))
    renderWithProviders(<AccountControls />, GUEST)
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await userEvent.click(await screen.findByText('Create account'))
    await fill('me@example.com', 'hunter22')
    await submit('Create account')
    expect(await screen.findByText('That email already has an account: sign in instead.')).toBeInTheDocument()
  })

  it('signs in to an existing account, and explains a wrong password', async () => {
    vi.mocked(signInWithEmail).mockRejectedValueOnce(Object.assign(new Error('x'), { code: 'auth/invalid-credential' }))
    renderWithProviders(<AccountControls />, GUEST)
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await fill('me@example.com', 'wrong')
    await submit('Sign in')
    expect(await screen.findByText('Wrong email or password.')).toBeInTheDocument()
    await userEvent.clear(screen.getByLabelText(/Password/))
    await userEvent.type(screen.getByLabelText(/Password/), 'right')
    await submit('Sign in')
    await waitFor(() => expect(signInWithEmail).toHaveBeenLastCalledWith('me@example.com', 'right'))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  })

  it('sends a password reset email', async () => {
    renderWithProviders(<AccountControls />, GUEST)
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await fill('me@example.com')
    await userEvent.click(screen.getByRole('button', { name: 'Forgot password?' }))
    expect(await screen.findByText(/a link to set a new password is on its way/)).toBeInTheDocument()
    expect(resetPassword).toHaveBeenCalledWith('me@example.com')
  })

  it('shows the signed-in email and signs out from its menu', async () => {
    renderWithProviders(<AccountControls />, LINKED)
    expect(screen.queryByRole('button', { name: 'Sign in' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'me@example.com' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Sign out' }))
    await waitFor(() => expect(signOut).toHaveBeenCalledOnce())
  })
})
