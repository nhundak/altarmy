/** Play time, as the API reports it in (fractional) seconds. */

/** Seconds as the results show them: "0.5 s", "12 s", "4 min 5 s", "1 h 20 min". */
export function formatSeconds(seconds: number): string {
  if (seconds < 9.95) return `${Math.round(seconds * 10) / 10} s`
  const total = Math.round(seconds)
  if (total < 60) return `${total} s`
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const rest = total % 60
  if (hours) return minutes ? `${hours} h ${minutes} min` : `${hours} h`
  return rest ? `${minutes} min ${rest} s` : `${minutes} min`
}

/** A spot on a zone map, as players read it: "55.9, 62.7". */
export const formatCoords = (x: number, y: number): string => `${x.toFixed(1)}, ${y.toFixed(1)}`

/** How a timing's breakdown kinds read, in the order they are listed. */
export const BREAKDOWN_LABELS: Readonly<Record<string, string>> = {
  travel: 'running',
  switch: 'switching characters',
  ah: 'auction house',
  vendor: 'vendors',
  mail: 'mail',
  craft: 'crafting',
  disenchant: 'disenchanting',
}

/** The breakdown's parts that take any time, longest first, as "crafting 2 min". */
export function breakdownParts(breakdown: Readonly<Record<string, number>>): string[] {
  return Object.entries(breakdown)
    .filter(([, seconds]) => seconds >= 0.05)
    .sort(([, a], [, b]) => b - a)
    .map(([kind, seconds]) => `${BREAKDOWN_LABELS[kind] ?? kind} ${formatSeconds(seconds)}`)
}
