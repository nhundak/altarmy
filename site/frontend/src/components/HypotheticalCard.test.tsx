import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { iconUrl, professionIcon } from '../lib/wow'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { HypotheticalCard } from './HypotheticalCard'

function show(over: Partial<Parameters<typeof HypotheticalCard>[0]> = {}) {
  mockApi({ '/api/status': status() })
  const props = {
    profession: 'Tailoring',
    skill: 45,
    professions: ['Cooking', 'Tailoring'],
    onChange: vi.fn(),
    onUpload: vi.fn(),
    ...over,
  }
  renderWithProviders(<HypotheticalCard {...props} />)
  return props
}

describe('HypotheticalCard', () => {
  it('shows the profession and skill a made-up character climbs from, what is assumed, and the upload', async () => {
    const { onUpload } = show()
    const card = screen.getByRole('region', { name: 'Skilling up' })
    expect(within(card).getByRole('combobox', { name: 'Profession' })).toHaveValue('Tailoring')
    expect(within(card).getByRole('textbox', { name: 'Current skill' })).toHaveValue('45')
    expect(within(card).getByRole('progressbar', { name: 'Your Tailoring skill' })).toBeInTheDocument()
    const note = within(card).getByText(/Doing our best with no character data/)
    const upload = within(card).getByRole('button', { name: 'Upload your characters' })
    expect(note.parentElement).toBe(upload.parentElement) // on one row
    await userEvent.click(upload)
    expect(onUpload).toHaveBeenCalled()
  })

  it('reports another skill once typed, within 1 and the highest there is, and another profession', async () => {
    const { onChange } = show()
    const skill = screen.getByRole('textbox', { name: 'Current skill' })
    await userEvent.clear(skill)
    await userEvent.type(skill, '120')
    await waitFor(() => expect(onChange).toHaveBeenCalledWith('Tailoring', 120))
    await userEvent.clear(skill)
    await userEvent.type(skill, '0')
    await new Promise((r) => setTimeout(r, 500))
    expect(onChange).toHaveBeenCalledTimes(1) // nothing below 1
    await userEvent.click(screen.getByRole('combobox', { name: 'Profession' }))
    const cooking = await screen.findByRole('option', { name: 'Cooking' })
    // each option after the game's icon of its profession
    expect(cooking.querySelector('img')?.getAttribute('src')).toBe(iconUrl(professionIcon('Cooking') ?? '', 'small'))
    await userEvent.click(cooking)
    expect(onChange).toHaveBeenLastCalledWith('Cooking', 45)
  })
})
