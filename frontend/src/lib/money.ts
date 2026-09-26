/** Money arrives from the API as integer copper; the `Money` component shows it as coins. */

import { splitMoney } from './wow'

const UNIT_LETTERS = { gold: 'g', silver: 's', copper: 'c' } as const

/** Copper as plain text where coin icons can't go (a dropdown's option): "27g 62s 42c", "-5s". */
export function formatMoney(copper: number): string {
  const text = splitMoney(Math.abs(copper))
    .map(({ unit, amount }) => `${amount}${UNIT_LETTERS[unit]}`)
    .join(' ')
  return copper < 0 ? `-${text}` : text
}

export function goldToCopper(gold: number): number {
  return Math.round(gold * 10000)
}

export function formatRoi(roi: number): string {
  return `${Math.round(roi * 100)}%`
}
