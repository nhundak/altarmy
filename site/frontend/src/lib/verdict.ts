import type { RankResult } from '../api/client'

/*
 * Whether a sale will sell, as the gold list says it: the server's verdict (steady, likely, unproven), why it is no
 * surer, and what about buying the reagents makes it less sure.
 */

export type VerdictLevel = RankResult['verdict']

export const VERDICT_LABEL: Readonly<Record<VerdictLevel, string>> = {
  steady: 'Steady',
  likely: 'Likely',
  unproven: 'Unproven',
}

/** A glyph per verdict, so it reads without colour too. */
export const VERDICT_GLYPH: Readonly<Record<VerdictLevel, string>> = { steady: '●', likely: '◐', unproven: '○' }

export const VERDICT_COLOR: Readonly<Record<VerdictLevel, string>> = { steady: 'teal', likely: 'yellow', unproven: 'orange' }

/** Each reason a sale is no surer, in a few words (the most actionable come first from the server). */
const REASONS: Readonly<Record<string, string>> = {
  lone: 'an asking price, not a price: one listing or a few, none seen selling',
  thin: 'few listed for what this sells',
  sold_out: 'none listed now, though some sold',
  unlisted: 'none listed, and none seen selling',
  few_days: 'too new to tell: scanned on too few days',
  unwatched: 'sales unknown: nobody scanned twice within 30 minutes lately',
  one_pair: 'all its sales seen between one pair of scans: maybe a single buyer',
  unsold: 'watched long enough, and none seen selling',
  few_sold: 'fewer seen selling than this sells',
  unknown: 'nothing known of it on the auction house',
  disenchant_unchecked: "the disenchant table isn't checked in game yet",
}

/** What about buying the reagents makes the sale less sure. */
const BUY_FLAGS: Readonly<Record<string, string>> = {
  short: 'it buys more than is listed',
  just_listed: 'its cheapest reagent was just listed, and may be gone',
}

/** A reason in a few words; unknown codes as they are. */
export const reasonText = (code: string): string => REASONS[code] ?? BUY_FLAGS[code] ?? code

/** The chip's short word under the verdict: its most actionable reason, cut to the part before a colon. */
export function verdictWord(r: Pick<RankResult, 'verdict_reasons' | 'buy_flags'>): string {
  const first = r.verdict_reasons[0] ?? r.buy_flags[0]
  return first ? reasonText(first).split(':')[0]! : ''
}

/** The whole verdict as a sentence, for a tooltip. */
export function verdictTitle(r: Pick<RankResult, 'verdict' | 'verdict_reasons' | 'buy_flags'>): string {
  const why = [...r.verdict_reasons, ...r.buy_flags].map(reasonText)
  const head = `${VERDICT_LABEL[r.verdict]} to sell`
  return why.length ? `${head}: ${why.join('; ')}` : r.verdict === 'steady' ? `${head}: it surely sells` : head
}
