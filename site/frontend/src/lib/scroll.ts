/*
 * Scrolling something into view while it animates into place: Motion animates layout with transforms, so the
 * element's layout box (offsetTop, offsetHeight) is already where it ends up, while its painted box is not.
 */

/** Room left above and below what is scrolled into view (px). */
const MARGIN = 16

/** The element's top in the document by layout alone, ignoring transforms. */
export function layoutTop(el: HTMLElement): number {
  let top = 0
  for (let e: HTMLElement | null = el; e; e = e.offsetParent as HTMLElement | null) top += e.offsetTop
  return top
}

/** Where the window should scroll to show `top`..`top + height` whole, moving as little as it takes (the top first
 * when it is taller than the window); null when it already shows. */
export function scrollTarget(top: number, height: number, scrollY: number, viewHeight: number): number | null {
  const from = top - MARGIN
  const to = top + height + MARGIN
  if (from >= scrollY && to <= scrollY + viewHeight) return null
  const target = from < scrollY || to - from > viewHeight ? from : to - viewHeight
  return Math.max(0, target)
}
