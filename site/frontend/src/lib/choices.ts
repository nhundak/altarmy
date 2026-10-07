import { createContext } from 'react'

/** The user's picks in a recipe's flow chart: tree path ('r.0', 'r.0.1'; 'sell' for the exit) -> option key
 * (vendor | ah | craft:<recipe id>, or an exit kind for the sale). The server ignores keys that don't fit. */
export type Choices = Readonly<Record<string, string>>

export const SELL_PATH = 'sell'

/** `choices` with `key` picked at `path`. Picks inside that branch are dropped: the branch has changed. */
export function choose(choices: Choices, path: string, key: string): Choices {
  const kept = Object.entries(choices).filter(([p]) => !p.startsWith(`${path}.`))
  return { ...Object.fromEntries(kept), [path]: key }
}

/** Makes a recipe's plan editable: places with alternatives get a menu of them. */
export type PlanEditing = {
  /** Picks option `key` at every tree path in `paths` (several when one step stands for several nodes). */
  onChoose: (paths: readonly string[], key: string) => void
  /** The user changed something: offer Reset. */
  modified: boolean
  onReset: () => void
  /** The changed plan is being re-costed. */
  pending: boolean
  error: string | null
}

/** Picks another source (or exit) at tree paths; absent when the plan is read-only. */
export const ChooseContext = createContext<PlanEditing['onChoose'] | undefined>(undefined)
