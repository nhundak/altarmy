import { describe, expect, it } from 'vitest'
import type { FlowNode, Step } from '../api/client'
import { bought, robeResult } from '../test/results'
import { nodeAt, stepSource } from './steps'

const step = (action: Step['action'], paths: string[]): Step => ({
  action,
  item_id: 1,
  name: 'Linen Cloth',
  quantity: 1,
  value: 0,
  via: '',
  who: '',
  paths,
})

const both = (vendor: number, ah: number): FlowNode['options'] => [
  { key: 'vendor', cost: vendor, source: 'vendor', via: '', crafter: '' },
  { key: 'ah', cost: ah, source: 'ah', via: '', crafter: '' },
]

// A robe from a bolt (crafted from 2 linen) and 3 more linen: linen sits at r.0.0 and r.1.
const tree: FlowNode = {
  ...robeResult.tree,
  inputs: [
    {
      ...robeResult.tree,
      item_id: 5,
      name: 'Bolt of Linen',
      via: 'Bolt of Linen',
      crafter: 'Tailor',
      mail_to: 'Smithy',
      options: [
        { key: 'craft:11', cost: 20, source: '', via: 'Bolt of Linen', crafter: 'Tailor' },
        { key: 'ah', cost: 90, source: 'ah', via: '', crafter: '' },
      ],
      option: 'craft:11',
      inputs: [bought(1, 'Linen Cloth', 2, 20, 'vendor', both(20, 30))],
    },
    bought(1, 'Linen Cloth', 3, 30, 'vendor', [...both(30, 45), { key: 'craft:9', cost: 99, source: '', via: 'X', crafter: '' }]),
  ],
}

describe('nodeAt', () => {
  it('walks the tree by path', () => {
    expect(nodeAt(tree, 'r')).toBe(tree)
    expect(nodeAt(tree, 'r.0.0')?.quantity).toBe(2)
    expect(nodeAt(tree, 'r.1')?.quantity).toBe(3)
    expect(nodeAt(tree, 'r.2')).toBeUndefined()
    expect(nodeAt(tree, 'sell')).toBeUndefined()
  })
})

describe('stepSource', () => {
  it("gives a step its node's options and the one taken", () => {
    expect(stepSource(step('craft', ['r.0']), tree)).toEqual({
      paths: ['r.0'],
      options: tree.inputs[0]!.options,
      option: 'craft:11',
      holder: 'Smithy',
    })
  })

  it('offers a merged step only what every node offers, costs summed', () => {
    expect(stepSource(step('buy', ['r.0.0', 'r.1']), tree)).toEqual({
      paths: ['r.0.0', 'r.1'],
      options: both(50, 75),
      option: 'vendor',
      holder: '',
    })
  })

  it('has nothing for the recipe’s own craft, mails, the sale or unknown paths', () => {
    expect(stepSource(step('craft', ['r']), tree)).toBeNull()
    expect(stepSource(step('mail', ['r.0']), tree)).toBeNull()
    expect(stepSource(step('sell', ['sell']), tree)).toBeNull()
    expect(stepSource(step('buy', ['r.7']), tree)).toBeNull()
    expect(stepSource(step('buy', []), tree)).toBeNull()
  })
})
