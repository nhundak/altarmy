/** Maps a step of a recipe's plan back to the reagent tree nodes it stands for, and their alternatives. */
import type { FlowNode, Step } from '../api/client'

/** The node at a tree path ('r', 'r.0', 'r.0.1'); undefined if there is none. */
export function nodeAt(tree: FlowNode, path: string): FlowNode | undefined {
  const [root, ...indices] = path.split('.')
  if (root !== 'r') return undefined
  let node: FlowNode | undefined = tree
  for (const i of indices) node = node?.inputs[Number(i)]
  return node
}

export type StepSource = {
  /** Where a pick applies: every node the step stands for. */
  paths: string[]
  /** The ways to get the items that all those nodes offer, costs summed, in the first node's order. */
  options: FlowNode['options']
  /** The key of the option taken. */
  option: string
  /** Who ends up holding the items (see `ItemNodeData.holder`). */
  holder: string
}

/** A buy or craft step's alternatives; null for mails, the sale, the recipe's own craft or unknown paths. */
export function stepSource(step: Step, tree: FlowNode): StepSource | null {
  if (step.action !== 'buy' && step.action !== 'craft') return null
  const nodes = step.paths.map((p) => nodeAt(tree, p))
  const [first] = nodes
  if (!first || !first.options.length || nodes.some((n) => !n)) return null
  const all = nodes as FlowNode[]
  const options = first.options.flatMap((o) => {
    const costs = all.map((n) => n.options.find((x) => x.key === o.key)?.cost)
    return costs.every((c) => c !== undefined) ? [{ ...o, cost: costs.reduce<number>((a, c) => a + c!, 0) }] : []
  })
  return { paths: step.paths, options, option: first.option, holder: first.mail_to || first.crafter }
}
