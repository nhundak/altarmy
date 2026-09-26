import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { characters, status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { ManualCharacterForm } from './ManualCharacterForm'

async function pick(label: string, option: string) {
  await userEvent.click(screen.getByRole('combobox', { name: label }))
  await userEvent.click(await screen.findByRole('option', { name: option }))
}

describe('ManualCharacterForm', () => {
  it('adds a character with its professions', { timeout: 15_000 }, async () => {
    const fetch = mockApi({
      '/api/characters': characters,
      '/api/professions': ['Cooking', 'Tailoring'],
      '/api/coverage': [],
      '/api/status': status(),
    })
    const created = vi.fn()
    renderWithProviders(<ManualCharacterForm onCreated={created} />)
    const add = screen.getByRole('button', { name: 'Add character' })
    expect(add).toBeDisabled()

    await userEvent.type(screen.getByRole('textbox', { name: 'Name' }), 'Handy')
    await pick('Class', 'Mage')
    await userEvent.type(screen.getByRole('combobox', { name: 'Realm' }), 'Classic Beta PvE')
    await userEvent.click(screen.getByRole('radio', { name: 'Alliance' }))
    await pick('Profession 1', 'Tailoring')
    const skill = screen.getByRole('textbox', { name: 'Skill 1' })
    await userEvent.clear(skill)
    await userEvent.type(skill, '120')
    await userEvent.click(screen.getByRole('button', { name: '+ Add a profession' }))
    expect(screen.getByRole('combobox', { name: 'Profession 2' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Remove profession 2' }))

    await userEvent.click(add)
    await waitFor(() => expect(created).toHaveBeenCalledOnce())
    const post = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'POST')
    expect(await post?.json()).toEqual({
      realm: 'Classic Beta PvE',
      faction: 'Alliance',
      name: 'Handy',
      class_file: 'MAGE',
      level: 60,
      professions: [{ name: 'Tailoring', rank: 120 }],
    })
  })

  it('shows why the server refused', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (r: Request) =>
        r.method === 'POST'
          ? new Response(JSON.stringify({ detail: 'At most 50 characters.' }), { status: 400 })
          : new Response(JSON.stringify([]), { status: 200 }),
      ),
    )
    renderWithProviders(<ManualCharacterForm />)
    await userEvent.type(screen.getByRole('textbox', { name: 'Name' }), 'Handy')
    await pick('Class', 'Druid')
    await userEvent.type(screen.getByRole('combobox', { name: 'Realm' }), 'Somewhere')
    await userEvent.click(screen.getByRole('button', { name: 'Add character' }))
    expect(await screen.findByText('At most 50 characters.')).toBeInTheDocument()
  })
})
