/** Turns a recipe's reagent tree into a laid-out React Flow graph: inputs on the left, the sale on the right. */
import dagre from '@dagrejs/dagre'
import type { Edge, Node } from '@xyflow/react'
import type { FlowNode, RankResult } from '../api/client'
import { SELL_PATH } from './choices'

export const NODE_WIDTH = 220
export const NODE_HEIGHT = 64
/** Room for a third line: the character who buys or crafts the item. */
export const NAMED_NODE_HEIGHT = 80

export type ItemNodeData = {
  itemId: number
  name: string
  quantity: number
  cost: number
  via: string
  /** Crafted by an essence conversion (the item's Use spell) rather than a profession recipe. */
  convert: boolean
  /** An enchant: `name` is the spell's, cast `crafts` times; no item is made. */
  enchant: boolean
  crafts: number
  made: number
  source: string
  /** Bought from a vendor: percent off from the buyer's Legacy talents (Bartering). */
  discount: number
  /** Bought from a vendor: percent off for the buyer's standing with the vendor's faction, and that faction. */
  repDiscount: number
  repFaction: string
  crafter: string
  isLeaf: boolean
  /** The tree path, which is also the node id: where a choice of source applies. */
  path: string
  /** Every way to get these items, cheapest first; `option` is the key of the one taken. */
  options: FlowNode['options']
  option: string
  /** Who ends up holding the items: whoever buys them, or whom the crafter mails them to. */
  holder: string
}
/** `seller`: who sells (or disenchants): the enchanter the output is mailed to, else the crafter. */
export type SellNodeData = {
  exit: string
  revenue: number
  profit: number
  quantity: number
  /** Expected extra units on top of `quantity` (Master Chef), counted in `revenue`. */
  bonus: number
  seller: string
  /** Each exit's best profit, best first. */
  options: RankResult['sell_options']
}
export type ItemFlowNode = Node<ItemNodeData, 'item'>
export type SellFlowNode = Node<SellNodeData, 'sell'>

export type Flow = {
  nodes: (ItemFlowNode | SellFlowNode)[]
  edges: Edge[]
  width: number
  height: number
}

/** Ids are tree paths ("r", "r.0", "r.0.1"), so an item used in two branches gets two nodes. Mailing between
 * characters (an intermediate to whoever uses it, the output to the enchanter selling it) is left to the step
 * list: the chart goes straight from one to the other. A flip's tree has no craft to show: its bought input is
 * sold directly. An enchant (sold via `skill`) makes nothing, so its chart ends with the
 * cast: no sale. */
export function buildFlow({
  tree,
  best_exit,
  revenue,
  profit,
  mail_to,
  sell_options,
  bonus_output = 0,
}: Pick<RankResult, 'tree' | 'best_exit' | 'revenue' | 'profit' | 'mail_to' | 'sell_options'> &
  Partial<Pick<RankResult, 'bonus_output'>>): Flow {
  const nodes: Flow['nodes'] = []
  const edges: Edge[] = []
  const edge = (source: string, target: string, quantity: number) =>
    edges.push({ id: `${source}->${target}`, source, target, label: `${quantity}x`, type: 'smoothstep' })

  let named = false
  const visit = (node: FlowNode, id: string) => {
    const { item_id, name, quantity, cost, via, crafts, made, source, discount, crafter, inputs, options, option } =
      node
    if (crafter) named = true
    nodes.push({
      id,
      type: 'item',
      position: { x: 0, y: 0 },
      data: {
        itemId: item_id,
        name,
        quantity,
        cost,
        via,
        convert: node.convert ?? false,
        enchant: node.enchant ?? false,
        crafts,
        made,
        source,
        discount,
        repDiscount: node.rep_discount,
        repFaction: node.rep_faction,
        crafter,
        isLeaf: inputs.length === 0,
        path: id,
        options,
        option,
        holder: node.mail_to || crafter,
      },
    })
    inputs.forEach((input, i) => {
      const child = `${id}.${i}`
      visit(input, child)
      edge(child, id, input.quantity)
    })
  }
  // A flip crafts nothing: what it buys (its one input) goes straight to the sale.
  const last = tree.flip && tree.inputs.length === 1 ? 'r.0' : 'r'
  if (last === 'r') visit(tree, 'r')
  else visit(tree.inputs[0], last)
  if (best_exit !== 'skill') {
    nodes.push({
      id: SELL_PATH,
      type: 'sell',
      position: { x: 0, y: 0 },
      data: {
        exit: best_exit,
        revenue,
        profit,
        quantity: tree.made,
        bonus: bonus_output,
        seller: mail_to || tree.crafter,
        options: sell_options,
      },
    })
    edge(last, SELL_PATH, tree.made)
  }

  const g = new dagre.graphlib.Graph()
  g.setGraph({ rankdir: 'LR', nodesep: 16, ranksep: 56, marginx: 0, marginy: 0 })
  g.setDefaultEdgeLabel(() => ({}))
  // One height for every node keeps each rank's boxes aligned.
  const nodeHeight = named ? NAMED_NODE_HEIGHT : NODE_HEIGHT
  for (const n of nodes) g.setNode(n.id, { width: NODE_WIDTH, height: nodeHeight })
  for (const e of edges) g.setEdge(e.source, e.target)
  dagre.layout(g)

  for (const n of nodes) {
    const { x, y } = g.node(n.id)
    // dagre gives centres; React Flow wants top-left corners. Fixed sizes let it skip measuring.
    n.position = { x: x - NODE_WIDTH / 2, y: y - nodeHeight / 2 }
    n.width = NODE_WIDTH
    n.height = nodeHeight
    // React Flow turns pointer events off on nodes that can't be selected or dragged; item tooltips need them.
    n.style = { pointerEvents: 'all' }
  }
  const { width = 0, height = 0 } = g.graph()
  return { nodes, edges, width, height }
}
