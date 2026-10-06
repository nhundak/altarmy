import type { CharacterGroup, Selection } from '../api/client'
import { type Holder, type ProfessionChoice, professionsOf } from './setup'

/*
 * The Profit page's paths: /profit (the start, then what the user is after), /profit/gold (making gold),
 * /profit/skill (which profession) and /profit/skill/<realm>/<character>/<profession> (one character skilling up one
 * profession: a link to it opens exactly that, switching the realm).
 */

export type ProfitView =
  | { kind: 'start' }
  | { kind: 'gold' }
  | { kind: 'skill' }
  /** `realm` and `profession` as slugs (`realmSlug`, `professionSlug`), `character` as named */
  | { kind: 'run'; realm: string; character: string; profession: string }

/** Lower-case words joined by dashes: "Classic Beta PvE" is "classic-beta-pve", "First Aid" "first-aid". */
const slug = (text: string) =>
  text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')

/** A realm and faction in a path: "dreamscythe-horde"; the realm alone for a house both factions share. */
export const realmSlug = ({ realm, faction }: Selection): string => slug(faction ? `${realm} ${faction}` : realm)

export const professionSlug = (name: string): string => slug(name)

/** What the Profit page shows at `pathname`; null for a path under it that means nothing. */
export function parseProfitPath(pathname: string): ProfitView | null {
  const parts = pathname.replace(/\/+$/, '').split('/').slice(2)
  const [first, ...rest] = parts
  if (first === undefined) return { kind: 'start' }
  if (first === 'gold' && rest.length === 0) return { kind: 'gold' }
  if (first !== 'skill') return null
  if (rest.length === 0) return { kind: 'skill' }
  if (rest.length !== 3 || rest.some((p) => !p)) return null
  try {
    const [realm, character, profession] = rest.map(decodeURIComponent) as [string, string, string]
    return { kind: 'run', realm, character, profession }
  } catch {
    return null // a malformed escape
  }
}

/** The path of a view of the Profit page. */
export function profitPath(view: ProfitView): string {
  switch (view.kind) {
    case 'start':
      return '/profit'
    case 'gold':
      return '/profit/gold'
    case 'skill':
      return '/profit/skill'
    case 'run':
      return `/profit/skill/${[view.realm, view.character, view.profession].map(encodeURIComponent).join('/')}`
  }
}

/** The path of `character` on `group`'s realm skilling up `profession`. */
export const runPath = (group: Selection, character: string, profession: string): string =>
  profitPath({ kind: 'run', realm: realmSlug(group), character, profession: professionSlug(profession) })

export type ResolvedRun = { group: CharacterGroup; professions: ProfessionChoice[]; choice: ProfessionChoice; holder: Holder }

/**
 * The character group, profession and character a run's path names, among the user's characters (`professionNames`
 * as `professionsOf` takes them); null when they have no such character, or it hasn't that profession.
 */
export function resolveRun(
  view: Extract<ProfitView, { kind: 'run' }>,
  groups: readonly CharacterGroup[],
  professionNames?: readonly string[],
): ResolvedRun | null {
  const realm = view.realm.toLowerCase()
  const group = groups.find((g) => realmSlug(g) === realm)
  if (!group) return null
  const professions = professionsOf(group, professionNames)
  const choice = professions.find((p) => professionSlug(p.name) === view.profession.toLowerCase())
  const holder = choice?.holders.find((h) => h.name.toLowerCase() === view.character.toLowerCase())
  return choice && holder ? { group, professions, choice, holder } : null
}
