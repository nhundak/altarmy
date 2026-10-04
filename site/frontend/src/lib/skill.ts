import type { RankResult } from '../api/client'

/*
 * Skilling up: what a skill point costs, and how far a run of a recipe goes (the crafts until another recipe would
 * give the character skilled up a cheaper skill point: the server's `runs`).
 */

/** What an expected skill point costs in copper (negative when the run earns gold); null when it gives none. */
export const perPoint = (r: Pick<RankResult, 'profit' | 'skill_ups'>): number | null =>
  r.skill_ups ? -r.profit / r.skill_ups : null

/** The results table's Craft until: the skill a run takes the crafter to and its crafts, "110 (~17 crafts)",
 * "110 (1 craft)"; just the crafts without a run. */
export function craftUntil(r: Pick<RankResult, 'crafts' | 'stop_skill'>): string {
  const crafts = r.crafts === 1 ? '1 craft' : `~${r.crafts} crafts`
  return r.stop_skill ? `${r.stop_skill} (${crafts})` : crafts
}

type Run = Pick<RankResult, 'crafts' | 'stop_skill' | 'stop_reason' | 'overtaken_by'>

/** How far to craft: "Craft until 85 skill (~17 times)", "(once)"; "Craft ~17 times" without the skill. */
export function runLead(r: Pick<Run, 'crafts' | 'stop_skill'>): string {
  const times = r.crafts === 1 ? 'once' : `~${r.crafts} times`
  return r.stop_skill ? `Craft until ${r.stop_skill} skill (${times})` : `Craft ${times}`
}

/** Why the run stops there, after the lead's ", at which point ": "this recipe becomes trivial", "you reach your
 * skill cap"; for a rival, the words around its name; null when the most crafts a run asks for cut it short. */
export function runReason(r: Pick<Run, 'stop_reason'>): string | null {
  switch (r.stop_reason) {
    case 'trivial':
      return 'this recipe becomes trivial'
    case 'cap':
      return 'you reach your skill cap'
    default:
      return null
  }
}

export const AT_WHICH_POINT = ', at which point '
export const CHEAPER = ' becomes a cheaper option'

/** The whole run as plain text: "Craft until 85 skill (~17 times), at which point Heavy Copper Maul becomes a
 * cheaper option", "…, at which point this recipe becomes trivial"; just the lead when the ceiling cut it short. */
export function runText(r: Run): string {
  const lead = runLead(r)
  if (r.stop_reason === 'rival') return `${lead}${AT_WHICH_POINT}${r.overtaken_by || 'another recipe'}${CHEAPER}`
  const reason = runReason(r)
  return reason ? `${lead}${AT_WHICH_POINT}${reason}` : lead
}

/** A plan's steps for `crafts` crafts instead of its own, each quantity (rounded up) and value in proportion: what the
 * checklist shows at once while the server plans that many. */
export function scaleRun<T extends Pick<RankResult, 'crafts' | 'steps'>>(r: T, crafts: number): T {
  if (crafts === r.crafts || r.crafts <= 0 || crafts <= 0) return r
  const f = crafts / r.crafts
  return {
    ...r,
    crafts,
    steps: r.steps.map((s) => ({ ...s, quantity: Math.ceil(s.quantity * f - 1e-9), value: Math.round(s.value * f) })),
  }
}

type PlainStep = Pick<RankResult['steps'][number], 'action' | 'name' | 'quantity' | 'via' | 'who' | 'enchant'>

/** One step as plain text, for the checklist copied into the game session. */
function stepText({ action, name, quantity, via, who, enchant }: PlainStep): string {
  const what = `${quantity}x ${name}`
  const line = (() => {
    switch (action) {
      case 'buy':
        return `Buy ${what} ${via === 'ah' ? 'on the AH' : 'from a vendor'}`
      case 'gather':
        return `Gather ${what}`
      case 'craft':
        return enchant ? `Cast ${name} ${quantity === 1 ? 'once' : `${quantity} times`}` : `Craft ${what}`
      case 'mail':
        return `Mail ${what} to ${via}`
      case 'sell':
        if (via === 'keep') return `Keep the ${what}`
        if (via === 'disenchant') return `Disenchant ${what}, sell the materials`
        return `Sell back ${what} ${via === 'ah' ? 'on the AH' : 'to a vendor'}`
      default:
        return `${action} ${what}`
    }
  })()
  return who ? `${who}: ${line}` : line
}

/** A plan's steps as a numbered plain-text checklist, under a heading. */
export function stepsText(heading: string, steps: readonly PlainStep[]): string {
  return [heading, ...steps.map((s, i) => `${i + 1}. ${stepText(s)}`)].join('\n')
}
