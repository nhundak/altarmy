import { z } from 'zod'

/** What the user wants from the search; it sets how results are ranked and presets some filters. */
export type Goal = 'profit' | 'budget' | 'skill'

export const goalSchema = z.enum(['profit', 'budget', 'skill'])

export const GOALS: readonly { key: Goal; title: string; blurb: string }[] = [
  {
    key: 'profit',
    title: 'Maximize profit',
    blurb: 'The most gold for each hour you play, whatever it costs up front.',
  },
  {
    key: 'budget',
    title: 'Make profit on a budget',
    blurb: 'The best profit from every single craft, for when gold to invest is short.',
  },
  {
    key: 'skill',
    title: 'Skill up for minimum expense',
    blurb: 'Only recipes that can still raise a skill, the cheapest first, even ones that lose a little gold.',
  },
]

/**
 * What a goal does to the search: the order the server ranks in, and the filters written when it is picked (the user
 * can change those afterwards). `minProfit` is in gold, as the filter is typed; 0.0001 is one copper, so only
 * profitable recipes. Budget and skill up will also weigh selling on the auction house down, once the ranking can.
 */
export const GOAL_SEARCH: Readonly<
  Record<Goal, { sort: 'profit' | 'rate'; includeTrivial: boolean; minProfit: number | null }>
> = {
  profit: { sort: 'rate', includeTrivial: true, minProfit: 0.0001 },
  budget: { sort: 'profit', includeTrivial: true, minProfit: 0.0001 },
  skill: { sort: 'profit', includeTrivial: false, minProfit: null },
}
