import { createContext, useContext } from 'react'

/** Selecting an item in the plan's Market section from anywhere in the plan (an item name in its steps or flow chart):
 * `has` the items the section shows, `select` opens the section on one. */
export interface MarketFocusValue {
  has: (itemId: number) => boolean
  select: (itemId: number) => void
}

export const MarketFocus = createContext<MarketFocusValue | null>(null)

/** The plan's Market section, when there is one around. */
export const useMarketFocus = () => useContext(MarketFocus)
