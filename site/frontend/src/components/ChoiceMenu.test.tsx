import { describe, expect, it } from 'vitest'
import { sellChoices } from './ChoiceMenu'

describe('sellChoices', () => {
  it('leaves keeping it out when there is another way to sell', () => {
    const choices = sellChoices(
      [
        { kind: 'vendor', profit: 10 },
        { kind: 'keep', profit: -50 },
      ],
      'vendor',
    )
    expect(choices.map((c) => c.key)).toEqual(['vendor'])
  })

  it('calls keeping it a dead loss when it is the only way', () => {
    const choices = sellChoices([{ kind: 'keep', profit: -50 }], 'keep')
    expect(choices.map((c) => c.label)).toEqual(['Dead loss (no vendor buys it)'])
  })
})
