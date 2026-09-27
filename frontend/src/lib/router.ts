import { useSyncExternalStore, type MouseEvent } from 'react'

/** The site's pages. Hosting (and the local server) serve index.html for each, so they are real paths. */
export const ROUTES = ['/', '/addon', '/profit', '/upload', '/manage'] as const
export type Route = (typeof ROUTES)[number]

const listeners = new Set<() => void>()

function subscribe(listener: () => void) {
  listeners.add(listener)
  window.addEventListener('popstate', listener)
  return () => {
    listeners.delete(listener)
    window.removeEventListener('popstate', listener)
  }
}

/** The page for a path; anything unknown is the main page. */
export function routeOf(pathname: string): Route {
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname
  return ROUTES.find((r) => r === path) ?? '/'
}

/** The current page; re-renders on navigation and the browser's back and forward buttons. */
export function useRoute(): Route {
  return useSyncExternalStore(subscribe, () => routeOf(window.location.pathname))
}

// The page shown now and the one before it (null on the first), so a page can tell where the visitor came from.
let shown: Route = routeOf(window.location.pathname)
let previous: Route | null = null

/** The page shown before the current one: null until the visitor has moved. */
export function previousRoute(): Route | null {
  return previous
}

/** Records a move to the page now at `window.location` (from `navigate` and the back and forward buttons). */
function moved() {
  const now = routeOf(window.location.pathname)
  if (now === shown) return
  previous = shown
  shown = now
}

window.addEventListener('popstate', moved)

/** Go to a page, adding a history entry. */
export function navigate(to: Route) {
  if (window.location.pathname !== to) window.history.pushState(null, '', to)
  moved()
  window.scrollTo?.({ top: 0 })
  listeners.forEach((l) => l())
}

/**
 * Props that make an anchor (or a Mantine Anchor/Button with `component="a"`) navigate within the app: a real
 * `href`, so modified clicks (new tab, copy link) still work, and plain left clicks handled here.
 */
export function linkProps(to: Route) {
  return {
    href: to,
    onClick: (e: MouseEvent<HTMLElement>) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
      e.preventDefault()
      navigate(to)
    },
  }
}
