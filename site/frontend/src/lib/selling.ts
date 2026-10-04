import type { ItemMap, RankResult } from '../api/client'

/*
 * What to watch for when posting a craft on the auction house: the price under which another exit pays more, the price
 * under which the session loses gold, what the plan counted on, and how much a disenchant adds to what is listed.
 */

/** Units the session makes (Master Chef's extra ones included). */
export const unitsMade = (r: Pick<RankResult, 'output_count' | 'crafts' | 'bonus_output'>): number =>
  r.output_count * r.crafts + r.bonus_output

/** The best way to sell other than the auction house, per unit after postage; null if there is none. */
export function fallback(r: Pick<RankResult, 'exits'>): { kind: string; value: number } | null {
  const others = r.exits.filter((e) => e.kind !== 'ah').map((e) => ({ kind: e.kind, value: e.value - e.postage }))
  return others.reduce<{ kind: string; value: number } | null>((best, e) => (!best || e.value > best.value ? e : best), null)
}

/** The lowest listing price at which the auction house still beats the best other exit (`cut` its share of a sale);
 * null when there is no other exit. */
export function floor(r: Pick<RankResult, 'exits'>, cut: number): number | null {
  const other = fallback(r)
  return other && other.value > 0 ? Math.ceil(other.value / (1 - cut)) : null
}

/** The listing price under which the session loses gold: what each unit cost, before the cut. */
export function breakEven(r: Pick<RankResult, 'cost' | 'output_count' | 'crafts' | 'bonus_output'>, cut: number): number {
  return Math.ceil(r.cost / Math.max(1, unitsMade(r)) / (1 - cut))
}

/** What the plan counted on for its AH sale: the price, and for how many of the units made. */
export function countedOn(
  r: Pick<RankResult, 'output_item_id' | 'output_count' | 'crafts' | 'bonus_output' | 'excess_units'>,
  items: ItemMap,
): { price: number | null; units: number; of: number } {
  const of = Math.round(unitsMade(r))
  return { price: items[r.output_item_id]?.ah_sell_price ?? null, units: Math.max(0, of - r.excess_units), of }
}

/** What disenchanting the session adds to each material's market: the expected units next to those listed. */
export function floodCheck(
  r: Pick<RankResult, 'exits' | 'output_count' | 'crafts' | 'bonus_output'>,
  items: ItemMap,
): { itemId: number; name: string; adds: number; listed: number | null }[] {
  const de = r.exits.find((e) => e.kind === 'disenchant')
  if (!de) return []
  const units = unitsMade(r)
  return de.materials.map((m) => ({
    itemId: m.item_id,
    name: m.name,
    adds: Math.round(units * m.chance * ((m.min_count + m.max_count) / 2)),
    listed: items[m.item_id]?.ah_quantity ?? null,
  }))
}
