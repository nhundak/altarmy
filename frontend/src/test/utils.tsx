import type { ReactElement } from 'react'
import { MantineProvider } from '@mantine/core'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render } from '@testing-library/react'
import { vi } from 'vitest'
import { FALLBACK_SESSION, SessionContext, type Session } from '../lib/session'
import { theme } from '../theme'

/** Sessions to render as: an anonymous guest, a user with an account (the default), or a site admin. */
export const GUEST: Session = { uid: 'guest', tier: 'free', admin: false }
export const LINKED: Session = FALLBACK_SESSION
export const ADMIN: Session = { uid: 'a1', tier: 'linked', admin: true }

/** Render with Mantine, a fresh query client and a signed-in `session` (default: `LINKED`). */
export function renderWithProviders(ui: ReactElement, session: Session = LINKED) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <MantineProvider theme={theme} env="test">
      <QueryClientProvider client={queryClient}>
        <SessionContext.Provider value={session}>{ui}</SessionContext.Provider>
      </QueryClientProvider>
    </MantineProvider>,
  )
}

/**
 * Stub fetch: each API path answers with its JSON body (or `await body(url, request)` for a function; read
 * the request's body from a clone, since tests read the original afterwards); unknown paths get a 404 with a
 * `detail`.
 */
export function mockApi(routes: Record<string, unknown>) {
  const fetch = vi.fn(async (request: Request) => {
    const url = new URL(request.url)
    const found = url.pathname in routes
    const route = routes[url.pathname]
    const body =
      typeof route === 'function' ? await (route as (url: URL, request: Request) => unknown)(url, request) : route
    return new Response(JSON.stringify(found ? body : { detail: `no mock for ${url.pathname}` }), {
      status: found ? 200 : 404,
      headers: { 'Content-Type': 'application/json' },
    })
  })
  vi.stubGlobal('fetch', fetch)
  return fetch
}

/** An element's text with the non-breaking spaces that pad money amounts shown as `_`, e.g. `_5 _0` for a padded 5s 0c. */
export const shown = (el: Element | null) => el?.textContent?.replaceAll('\u00a0', '_')
