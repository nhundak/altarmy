import { z } from 'zod'
import type { CharacterGroup } from '../api/client'
import type { Exit, Unlearned } from '../api/queries'

/*
 * The Profit page's setup: a few questions asked before the search, each setting one thing about it. What the user is
 * after (gold, or skill in one profession); for gold, how they are willing to sell.
 */

export const aimSchema = z.enum(['gold', 'skill'])
export const sellingSchema = z.enum(['reliable', 'any'])
export type Aim = z.infer<typeof aimSchema>
export type Selling = z.infer<typeof sellingSchema>

/** The answers so far; the ones a changed aim no longer asks are kept for when it comes back. Keys it no longer
 * knows (a budget, from before that question was dropped) are stripped when read. */
export const setupSchema = z.object({
  aim: aimSchema,
  profession: z.string().optional(),
  /** Which of the profession's holders are being skilled up; unset: all of them. */
  characters: z.array(z.string()).optional(),
  selling: sellingSchema.optional(),
})
export type Setup = z.infer<typeof setupSchema>
export type Step = 'aim' | 'profession' | 'selling'

/** Every way to sell, in the order the filters list them. */
export const ALL_EXITS: readonly Exit[] = ['vendor', 'disenchant', 'ah']
/** Ways to sell that never leave the user holding stock: a vendor always pays, enchanting materials always sell. */
const RELIABLE_EXITS: readonly Exit[] = ['vendor', 'disenchant']

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
  selling: 'How do you want to sell?',
}

export const AIMS: readonly Card<Aim>[] = [
  {
    key: 'gold',
    title: 'Make gold',
    blurb: 'The most gold for each hour of play.',
    details: 'Emphasis is placed on minimizing time wasted travelling and switching characters.',
  },
  {
    key: 'skill',
    title: 'Skill up',
    blurb: 'Raise a profession, or any, for as little gold as possible.',
    details:
      'Recipes that can no longer give a skill point are hidden. The rest are ranked by what an expected skill point costs: orange recipes always give one, yellow and green ones less often.',
  },
]

export const SELLING: readonly Card<Selling>[] = [
  {
    key: 'reliable',
    title: 'Only what reliably sells',
    blurb: 'Sell to a vendor, or disenchant and sell the materials.',
    details:
      "Enchanting materials have steady prices and always find buyers, and a vendor always pays. Margins are smaller, but you won't be left holding stock.",
  },
  {
    key: 'any',
    title: 'Anything that might sell',
    blurb: 'Also sell crafted items on the auction house.',
    details: "We'll show you the theoretical profits from selling on the auction house,",
    caution: 'but you must take an active role in:',
    points: ['Evaluating which items you think are likely to sell', 'Taking care not to flood the market'],
  },
]

/** The profession answer that skills up any profession: every recipe that gives someone a skill point. */
export const ANY_PROFESSION = 'any'

/** One character having a profession, at what skill. */
export type Holder = { name: string; classFile: string; rank: number; maxRank: number }

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
      entry.holders.push({ name: c.name, classFile: c.class_file, rank: p.rank, maxRank: p.max_rank })
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
    if (setup.profession?.toLowerCase() === ANY_PROFESSION) return professions.length ? null : 'profession'
    return skillCrafters(setup, professions).length ? null : 'profession'
  }
  return setup.selling ? null : 'selling'
}

/**
 * The characters being skilled up: the picked profession's holders on the realm (those picked, if some were), every
 * holder of a profession for any profession, none when making gold. Only they do a recipe's final craft.
 */
export function skillCrafters(setup: Setup | null, professions: readonly ProfessionChoice[]): string[] {
  if (setup?.aim !== 'skill' || !setup.profession) return []
  const holders =
    setup.profession === ANY_PROFESSION
      ? professions.flatMap((p) => p.holders)
      : (professionIn(professions, setup.profession)?.holders ?? [])
  const picked = setup.profession === ANY_PROFESSION ? undefined : setup.characters
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
    case 'selling':
      return { ...base, selling: sellingSchema.parse(value) }
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
  /** which recipes nobody has learned count: skilling up looks at what can be trained now too */
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
        { includeTrivial: false, minProfit: null, minRoi: null, exits: [...RELIABLE_EXITS], unlearned: 'now' }
      : {
          includeTrivial: true,
          minProfit: 0.0001,
          minRoi: 0,
          exits: [...(setup.selling === 'reliable' ? RELIABLE_EXITS : ALL_EXITS)],
          unlearned: 'none',
        }
  switch (step) {
    case 'aim':
      return all
    case 'selling':
      return { exits: all.exits }
    case 'profession':
      return {}
  }
}

/** How the server ranks for this setup: gold per hour, or the cheapest expected skill point. */
export const rankSort = (setup: Setup | null): 'rate' | 'skill' => (setup?.aim === 'skill' ? 'skill' : 'rate')

/** The professions the search is narrowed to: the one being skilled up (none for any profession). */
export const rankProfessions = (setup: Setup | null): string[] =>
  setup?.aim === 'skill' && setup.profession && setup.profession !== ANY_PROFESSION ? [setup.profession] : []

const SELLING_TEXT: Readonly<Record<Selling, string>> = {
  reliable: 'only what reliably sells',
  any: 'anything that might sell',
}

/** The answers in a few words each, in question order, for the folded summary: "Making gold · …". */
export function stripParts(setup: Setup): { step: Step; text: string }[] {
  const parts: { step: Step; text: string }[] = []
  if (setup.aim === 'skill') {
    parts.push({ step: 'aim', text: 'Skilling up' })
    if (setup.profession) {
      const who = setup.profession !== ANY_PROFESSION && setup.characters
      parts.push({
        step: 'profession',
        text:
          setup.profession === ANY_PROFESSION
            ? 'Any profession'
            : who
              ? `${setup.profession} (${who.join(', ')})`
              : setup.profession,
      })
    }
    return parts
  }
  parts.push({ step: 'aim', text: 'Making gold' })
  if (setup.selling) parts.push({ step: 'selling', text: SELLING_TEXT[setup.selling] })
  return parts
}
