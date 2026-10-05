import { z } from 'zod'
import type { CharacterGroup } from '../api/client'
import type { Exit, Unlearned } from '../api/queries'
import { writeStored } from './storage'
import { craftingTalents, type CraftingTalent } from './talents'

/*
 * The Profit page's setup: a few questions asked before the search, each setting one thing about it. What the user is
 * after (gold, or skill in one profession), and for skill which profession. Making gold asks nothing more: its list shows
 * what playing it safe and what the auction house make side by side, and the user sorts by either.
 */

export const aimSchema = z.enum(['gold', 'skill'])
const sellingSchema = z.enum(['reliable', 'any'])
export type Aim = z.infer<typeof aimSchema>

/** The answers so far; the ones a changed aim no longer asks are kept for when it comes back. Keys it no longer
 * knows (a budget, from before that question was dropped) are stripped when read. */
export const setupSchema = z.object({
  aim: aimSchema,
  profession: z.string().optional(),
  /** Which of the profession's holders is being skilled up (one; several from before one climbed at a time); unset:
   * the one who has it. */
  characters: z.array(z.string()).optional(),
  /** How to sell, from when making gold asked; no longer asked or read (both ways show side by side). */
  selling: sellingSchema.optional(),
})
export type Setup = z.infer<typeof setupSchema>
export type Step = 'aim' | 'profession'

/** Every way to sell, in the order the filters list them. */
export const ALL_EXITS: readonly Exit[] = ['vendor', 'disenchant', 'ah']
/** Skilling up sells what is made to a vendor or disenchants it (when someone can), else keeps it. */
export const SKILL_EXITS: readonly Exit[] = ['vendor', 'disenchant', 'keep']

export type Card<K extends string> = {
  key: K
  title: string
  blurb: string
  details?: string
  /** Said after `details`, highlighted, and followed by `points` as a list. */
  caution?: string
  points?: readonly string[]
}

export const STEP_QUESTION: Readonly<Record<Step, string>> = {
  aim: 'What are you after?',
  profession: 'Which profession?',
}

export const AIMS: readonly Card<Aim>[] = [
  {
    key: 'gold',
    title: 'Make gold',
    blurb: 'The most profitable recipes your characters can craft.',
  },
  {
    key: 'skill',
    title: 'Skill up',
    blurb: 'Raise a profession, or any, for as little gold as possible.',
    details:
      'Each recipe is counted as the crafts until it turns green for you, ranked by what an expected skill point costs: orange recipes always give one, yellow and green ones less often.',
  },
]

/** One character having a profession, at what skill, and the Legacy talents that matter to it (`craftingTalents`). */
export type Holder = {
  name: string
  classFile: string
  rank: number
  maxRank: number
  talents?: CraftingTalent[]
}

/** A profession someone on the realm has, and who. */
export type ProfessionChoice = { name: string; holders: Holder[] }

/**
 * The professions the group's characters have, by name, each once, with who has it at what skill. With `withRecipes`
 * (the version's professions that have recipes), only those: gathering skills have nothing to rank.
 */
export function professionsOf(
  group: CharacterGroup | undefined,
  withRecipes?: readonly string[],
): ProfessionChoice[] {
  const ranked = withRecipes && new Set(withRecipes.map((n) => n.toLowerCase()))
  const byName = new Map<string, ProfessionChoice>()
  for (const c of group?.characters ?? []) {
    for (const p of c.professions) {
      const key = p.name.toLowerCase()
      if (ranked && !ranked.has(key)) continue
      const entry = byName.get(key) ?? { name: p.name, holders: [] }
      const talents = craftingTalents(c.talents, p.name)
      entry.holders.push({
        name: c.name,
        classFile: c.class_file,
        rank: p.rank,
        maxRank: p.max_rank,
        ...(talents.length ? { talents } : {}),
      })
      byName.set(key, entry)
    }
  }
  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
}

/** Whether anyone in the group can disenchant. */
export const hasEnchanter = (group: CharacterGroup | undefined): boolean =>
  group?.characters.some((c) => c.professions.some((p) => p.name.toLowerCase() === 'enchanting')) ?? false

const professionIn = (professions: readonly ProfessionChoice[], name: string | undefined) =>
  professions.find((p) => p.name.toLowerCase() === name?.toLowerCase())

/**
 * The first question still to answer, or null when the setup is complete. Skilling up needs characters (their
 * professions) and a profession someone on the selected realm has (`professions`), one of the characters picked among
 * them, so it asks again when those change.
 */
export function nextStep(
  setup: Setup | null,
  professions: readonly ProfessionChoice[],
  noCharacters: boolean,
): Step | null {
  if (setup === null) return 'aim'
  if (setup.aim === 'skill') {
    if (noCharacters) return 'aim'
    return skillCrafters(setup, professions).length ? null : 'profession'
  }
  return null
}

/**
 * The characters being skilled up: the picked profession's holders on the realm (those picked, if some were);
 * none when making gold. Only they do a recipe's final craft.
 */
export function skillCrafters(setup: Setup | null, professions: readonly ProfessionChoice[]): string[] {
  if (setup?.aim !== 'skill' || !setup.profession) return []
  const holders = professionIn(professions, setup.profession)?.holders ?? []
  const picked = setup.characters
  const names = holders.map((h) => h.name).filter((n) => !picked || picked.includes(n))
  return [...new Set(names)].sort()
}

/** `setup` with `step` answered `value` (the key of the card picked); a profession with the `characters` picked among
 * its holders (unset: all of them). */
export function answer(setup: Setup | null, step: Step, value: string, characters?: string[]): Setup {
  const base: Setup = setup ?? { aim: step === 'profession' ? 'skill' : 'gold' }
  switch (step) {
    case 'aim':
      return { ...base, aim: aimSchema.parse(value) }
    case 'profession':
      return { ...base, profession: value, characters }
  }
}

/** The search filters a setup presets; the user may change them afterwards. Money in gold, as typed. */
export type Presets = {
  includeTrivial: boolean
  /** 0.0001 is one copper: only profitable recipes */
  minProfit: number | null
  /** percent; null lets losing recipes (negative ROI) through */
  minRoi: number | null
  exits: Exit[]
  /** which recipes nobody has learned count: skilling up looks at what can be trained too */
  unlearned: Unlearned
}

/**
 * The filters to write when `step` was just answered: an aim writes them all (answers kept from before count, missing
 * ones mean no limit), a later answer only the filter it is about, so the user's other changes stay.
 */
export function presetsFor(setup: Setup, step: Step): Partial<Presets> {
  const all: Presets =
    setup.aim === 'skill'
      ? // losing recipes may be the only way to skill up: no lower bound on profit or ROI; what is made along the way
        // is sold where it surely sells, not left on the auction house
        { includeTrivial: false, minProfit: null, minRoi: null, exits: [...SKILL_EXITS], unlearned: 'train' }
      : {
          includeTrivial: true,
          minProfit: 0.0001,
          minRoi: 0,
          exits: [...ALL_EXITS],
          unlearned: 'none',
        }
  switch (step) {
    case 'aim':
      return all
    case 'profession':
      return {}
  }
}

/**
 * Where an aim keeps one of its search filters: making gold and skilling up each remember their own, so answering one
 * never overwrites the other's. `legacySearchKey` is where every filter was kept before, read while an aim has none.
 */
export const searchKey = (aim: Aim, name: string) => `altarmy-profit.search.${aim}.${name}`
export const legacySearchKey = (name: string) => `altarmy-profit.search.${name}`

/** Store the filters an answer presets under the aim's keys, for its search to start from. */
export function storePresets(aim: Aim, presets: Partial<Presets>) {
  for (const [name, value] of Object.entries(presets)) {
    if (value !== undefined) writeStored(searchKey(aim, name), value)
  }
}

/** How the server ranks for this setup: the most profit, or the cheapest expected skill point. */
export const rankSort = (setup: Setup | null): 'profit' | 'skill' => (setup?.aim === 'skill' ? 'skill' : 'profit')

/** The professions the search is narrowed to: the one being skilled up. */
export const rankProfessions = (setup: Setup | null): string[] =>
  setup?.aim === 'skill' && setup.profession ? [setup.profession] : []

/** The answers in a few words each, in question order, for the folded summary: "Making gold · …". */
export function stripParts(setup: Setup): { step: Step; text: string }[] {
  const parts: { step: Step; text: string }[] = []
  if (setup.aim === 'skill') {
    parts.push({ step: 'aim', text: 'Skilling up' })
    if (setup.profession) {
      const who = setup.characters
      parts.push({ step: 'profession', text: who ? `${setup.profession} (${who.join(', ')})` : setup.profession })
    }
    return parts
  }
  parts.push({ step: 'aim', text: 'Making gold' })
  return parts
}
