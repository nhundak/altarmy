import { describe, expect, it } from 'vitest'
import type { FlowNode } from '../api/client'
import { bought } from '../test/results'
import { NAMED_NODE_HEIGHT, NODE_HEIGHT, NODE_WIDTH, buildFlow } from './flow'

const boltOptions: FlowNode['options'] = [
  { key: 'craft:11', cost: 60, source: '', via: 'Bolt of Linen', crafter: '', seconds: 0, convert: false },
  { key: 'ah', cost: 300, source: 'ah', via: '', crafter: '', seconds: 0, convert: false },
]

// Green Robe from 3 crafted Bolts of Linen (from 6 Linen) and 1 bought Coarse Thread.
const tree: FlowNode = {
  item_id: 3,
  name: 'Green Robe',
  quantity: 1,
  cost: 65,
  via: 'Green Robe',
  crafts: 1,
  made: 1,
  source: '',
  crafter: '',
  mail_to: '',
  postage: 0,
  discount: 0,
  rep_discount: 0,
  rep_faction: '',
  seconds: 0,
  options: [],
  option: '',
  convert: false,
  flip: false,
  enchant: false,
  short: 0,
  inputs: [
    {
      item_id: 5,
      name: 'Bolt of Linen',
      quantity: 3,
      cost: 60,
      via: 'Bolt of Linen',
      crafts: 3,
      made: 3,
      source: '',
      crafter: '',
      mail_to: '',
      postage: 0,
      discount: 0,
      rep_discount: 0,
      rep_faction: '',
      seconds: 0,
      options: boltOptions,
      option: 'craft:11',
      convert: false,
      flip: false,
      enchant: false,
      short: 0,
      inputs: [bought(1, 'Linen Cloth', 6, 60)],
    },
    bought(2, 'Coarse Thread', 1, 5),
  ],
}

describe('buildFlow', () => {
  const sellOptions = [
    { kind: 'ah', profit: 435 },
    { kind: 'vendor', profit: 100 },
  ]
  const sale = { best_exit: 'ah', revenue: 500, profit: 435, mail_to: '', sell_options: sellOptions }
  const flow = buildFlow({ tree, ...sale })
  const byId = new Map(flow.nodes.map((n) => [n.id, n]))

  it('sends what a flip buys straight to the sale', () => {
    const robe = bought(3, 'Green Robe', 7, 3500)
    const flipped = buildFlow({
      tree: { ...robe, via: 'Green Robe', source: '', crafts: 7, made: 7, flip: true, inputs: [robe] },
      ...sale,
      best_exit: 'disenchant',
    })
    expect(flipped.nodes.map((n) => [n.id, n.type])).toEqual([
      ['r.0', 'item'],
      ['sell', 'sell'],
    ])
    expect(flipped.edges.map((e) => [e.source, e.target, e.label])).toEqual([['r.0', 'sell', '7x']])
  })

  it('makes one node per tree item plus the sale', () => {
    expect(flow.nodes.map((n) => [n.id, n.type])).toEqual([
      ['r', 'item'],
      ['r.0', 'item'],
      ['r.0.0', 'item'],
      ['r.1', 'item'],
      ['sell', 'sell'],
    ])
    expect(byId.get('r.0')?.data).toMatchObject({ itemId: 5, quantity: 3, via: 'Bolt of Linen', crafts: 3 })
    expect(byId.get('r.1')?.data).toMatchObject({ itemId: 2, source: 'ah', isLeaf: true })
    expect(byId.get('sell')?.data).toMatchObject({ exit: 'ah', revenue: 500, profit: 435 })
  })

  it('gives item nodes their path and options, and the sale its exits', () => {
    expect(byId.get('r')?.data).toMatchObject({ path: 'r', options: [], option: '' })
    expect(byId.get('r.0')?.data).toMatchObject({ path: 'r.0', options: boltOptions, option: 'craft:11', holder: '' })
    expect(byId.get('r.0.0')?.data).toMatchObject({ path: 'r.0.0', option: 'ah' })
    expect(byId.get('sell')?.data).toMatchObject({ options: sellOptions })
  })

  it('points edges from each input to what it is used for, labelled with the quantity', () => {
    expect(flow.edges.map((e) => [e.source, e.target, e.label])).toEqual([
      ['r.0.0', 'r.0', '6x'],
      ['r.0', 'r', '3x'],
      ['r.1', 'r', '1x'],
      ['r', 'sell', '1x'],
    ])
  })

  it('lays out left to right: inputs before the crafts that use them', () => {
    for (const e of flow.edges) {
      const [source, target] = [byId.get(e.source), byId.get(e.target)]
      expect(source!.position.x + NODE_WIDTH).toBeLessThan(target!.position.x)
    }
    for (const n of flow.nodes) expect(n.position.x).toBeGreaterThanOrEqual(0)
    expect(flow.nodes.every((n) => n.height === NODE_HEIGHT)).toBe(true) // no character names
    expect(flow.width).toBeGreaterThanOrEqual(4 * NODE_WIDTH)
    expect(flow.height).toBeGreaterThan(0)
  })

  it('leaves out mailing an intermediate crafted by another character: the step list says it', () => {
    const [bolt, thread] = tree.inputs
    const split: FlowNode = {
      ...tree,
      crafter: 'Smithy',
      inputs: [{ ...bolt!, crafter: 'Weaver', mail_to: 'Smithy', postage: 30 }, thread!],
    }
    const flow = buildFlow({ ...sale, tree: split, profit: 405 })
    expect(flow.nodes.map((n) => n.type)).not.toContain('mail')
    // Smithy holds the bolts in the end: another source would be bought by, or mailed to, Smithy
    expect(flow.nodes.find((n) => n.id === 'r.0')?.data).toMatchObject({ crafter: 'Weaver', holder: 'Smithy' })
    expect(flow.nodes.every((n) => n.height === NAMED_NODE_HEIGHT)).toBe(true)
    expect(flow.edges.map((e) => [e.source, e.target, e.label])).toEqual([
      ['r.0.0', 'r.0', '6x'],
      ['r.0', 'r', '3x'],
      ['r.1', 'r', '1x'],
      ['r', 'sell', '1x'],
    ])
  })

  it('goes straight to the sale when the output is mailed to an enchanter, naming them on the sale', () => {
    const mailed = buildFlow({ ...sale, tree, best_exit: 'disenchant', revenue: 500, profit: 405, mail_to: 'Enchy' })
    expect(mailed.nodes.find((n) => n.id === 'sell')?.data).toMatchObject({ seller: 'Enchy' })
    expect(mailed.nodes.map((n) => n.type)).not.toContain('mail')
    expect(mailed.edges.at(-1)).toMatchObject({ source: 'r', target: 'sell', label: '1x' })
  })
})

describe('buildFlow: an enchant', () => {
  it('ends with the cast: no sale', () => {
    const dust = bought(1, 'Strange Dust', 10, 1000)
    const flow = buildFlow({
      tree: { ...dust, item_id: 0, name: 'Enchant Bracer', via: 'Enchant Bracer', source: '', crafts: 5, made: 5, enchant: true, inputs: [dust] },
      best_exit: 'skill',
      revenue: 0,
      profit: -1000,
      mail_to: '',
      sell_options: [{ kind: 'skill', profit: -1000 }],
    })
    expect(flow.nodes.map((n) => [n.id, n.type])).toEqual([
      ['r', 'item'],
      ['r.0', 'item'],
    ])
    expect(flow.nodes[0]?.data).toMatchObject({ name: 'Enchant Bracer', enchant: true, crafts: 5 })
    expect(flow.edges.map((e) => [e.source, e.target])).toEqual([['r.0', 'r']])
  })
})
