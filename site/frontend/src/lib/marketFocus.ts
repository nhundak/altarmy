import { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { RankResult } from '../api/client'
import { defaultItem, marketItems } from './market'

/** Selecting an item in the plan's Market section from anywhere in the plan (an item name in its steps or flow chart):
 * `has` the items the section shows, `select` opens the section on one. */
export interface MarketFocusValue {
  has: (itemId: number) => boolean
  select: (itemId: number) => void
}

export const MarketFocus = createContext<MarketFocusValue | null>(null)

/** The plan's Market section, when there is one around. */
export const useMarketFocus = () => useContext(MarketFocus)

/** Who the section is for: a gold row (what is sold decides it) or a skill run (what is bought does). */
export type MarketMode = 'gold' | 'skill'

/**
 * The Market section's state, shared by its header, its body and the plan around it: the plan's items, the one
 * selected (the default while the user picked none, or the one picked has left the plan), and the `focus` that item
 * names in the plan's steps and flow chart use to select an item (`open` opens the section; it is then scrolled into
 * view through `ref`). Without a result (a plan still on its way) there is nothing to show.
 */
export function useMarket(result: RankResult | undefined, mode: MarketMode, open: () => void) {
  const list = useMemo(() => (result ? marketItems(result) : []), [result])
  const [picked, setPicked] = useState<number | null>(null)
  const selected =
    picked !== null && list.some((m) => m.itemId === picked)
      ? picked
      : result
        ? defaultItem(list, result, mode)
        : null
  const ref = useRef<HTMLDivElement>(null)
  const openRef = useRef(open)
  openRef.current = open
  const [scrolls, setScrolls] = useState(0)
  useEffect(() => {
    if (!scrolls) return
    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    ref.current?.scrollIntoView?.({ block: 'nearest', behavior: reduced ? 'auto' : 'smooth' })
  }, [scrolls])
  const focus = useMemo<MarketFocusValue>(() => {
    const ids = new Set(list.map((m) => m.itemId))
    return {
      has: (id) => ids.has(id),
      select: (id) => {
        setPicked(id)
        openRef.current()
        setScrolls((n) => n + 1)
      },
    }
  }, [list])
  return { list, selected, select: setPicked, focus, ref }
}
