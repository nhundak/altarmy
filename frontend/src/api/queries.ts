import { useEffect, useRef } from 'react'
import { notifications } from '@mantine/notifications'
import { keepPreviousData, useMutation, useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  call,
  client,
  type Evaluation,
  type ManualCharacter,
  type Selection,
  type Sources,
  type Status,
  type TimeConfig,
  type UpdateResult,
} from './client'
import { GAME_VERSION } from '../lib/gameVersion'
import type { Choices } from '../lib/choices'
import { importedSince, readSyncSeen, syncSeen, writeSyncSeen } from '../lib/syncNotice'

/** The `game_version` query parameter every per-game route takes. */
const GV = { params: { query: { game_version: GAME_VERSION } } }

/**
 * The server status. Fetching it also makes the server re-import the Alt Army and Auctionator files if WoW
 * rewrote them (on logout or /reload), so poll it, and refetch when the user comes back from the game.
 */
export function useStatus() {
  return useQuery({
    queryKey: ['status', GAME_VERSION],
    queryFn: () => call(client.GET('/api/status', GV)),
    refetchInterval: 30_000,
    refetchOnWindowFocus: true,
  })
}

/**
 * Part of the keys of data that imports and merges affect: the user's data version (bumped whenever a sync or upload
 * re-imported something) and the selected auction house's price version (bumped by the hourly merge).
 */
export function useDataVersion() {
  const status = useStatus().data
  return status && `${status.data_version}.${status.price_version ?? 0}`
}

export function useCharacters() {
  const version = useDataVersion()
  return useQuery({
    queryKey: ['characters', GAME_VERSION, version],
    queryFn: () => call(client.GET('/api/characters', GV)),
    enabled: version !== undefined,
    placeholderData: keepPreviousData,
  })
}

/** Every profession of the game's recipes (fixed until the next game data update). */
export function useProfessions() {
  return useQuery({
    queryKey: ['professions', GAME_VERSION],
    queryFn: () => call(client.GET('/api/professions', GV)),
    staleTime: Infinity,
  })
}

/** Add a character by hand (it knows every recipe of its professions) and select its realm. */
export function useCreateCharacter() {
  const invalidate = useInvalidateAll()
  return useMutation({
    mutationFn: (body: ManualCharacter) => call(client.POST('/api/characters', { ...GV, body })),
    onSuccess: () => invalidate(),
  })
}

export function useDeleteCharacter() {
  const invalidate = useInvalidateAll()
  return useMutation({
    mutationFn: ({ realm, name }: { realm: string; name: string }) =>
      call(client.DELETE('/api/characters', { params: { query: { game_version: GAME_VERSION, realm, name } } })),
    onSuccess: () => invalidate(),
    onError: showError('Could not remove the character'),
  })
}

export type Exit = 'vendor' | 'disenchant' | 'ah'

/** `/api/rank` parameters: money in copper, ROI as a fraction (0.5 = 50%), `null` for no bound. */
export type RankParams = {
  includeUnlearned: boolean
  /** false: only recipes that can give the crafter a skillup */
  includeTrivial: boolean
  exits: Exit[]
  minCost: number | null
  maxCost: number | null
  minProfit: number | null
  maxProfit: number | null
  minRoi: number | null
  maxRoi: number | null
  /** only recipes of these professions; empty for every one */
  professions: string[]
  /** best profit per craft first, or per hour of play */
  sort: 'profit' | 'rate'
  top: number
}

const orUndefined = <T>(v: T | null) => v ?? undefined

/** Ranked recipes for the selected realm/faction's characters (every recipe without characters). */
export function useRank(params: RankParams) {
  const version = useDataVersion()
  return useQuery({
    queryKey: ['rank', GAME_VERSION, version, params],
    queryFn: () =>
      call(
        client.GET('/api/rank', {
          params: {
            query: {
              game_version: GAME_VERSION,
              include_unlearned: params.includeUnlearned,
              include_trivial: params.includeTrivial,
              exits: params.exits,
              min_cost: orUndefined(params.minCost),
              max_cost: orUndefined(params.maxCost),
              min_profit: orUndefined(params.minProfit),
              max_profit: orUndefined(params.maxProfit),
              min_roi: orUndefined(params.minRoi),
              max_roi: orUndefined(params.maxRoi),
              professions: params.professions.length ? params.professions : undefined,
              sort: params.sort === 'rate' ? 'rate' : undefined,
              top: params.top,
            },
          },
        }),
      ),
    enabled: version !== undefined,
    placeholderData: keepPreviousData,
  })
}

/** What `/api/evaluate` needs besides the choices: the search's settings, and the data version its results
 * came from (so a sync re-costs the user's changed plans too). */
export type EvaluateParams = Pick<RankParams, 'includeUnlearned' | 'includeTrivial' | 'exits'> & { version?: string }

export type EvaluationState = { data?: Evaluation; isFetching: boolean; error: Error | null }

/** Each recipe re-costed with the user's choices, by recipe id. While a new choice loads, the recipe's
 * previous evaluation stays in `data`. */
export function useEvaluations(
  choices: Readonly<Record<number, Choices>>,
  { includeUnlearned, includeTrivial, exits, version }: EvaluateParams,
): Readonly<Record<number, EvaluationState>> {
  const ids = Object.keys(choices).map(Number)
  return useQueries({
    queries: ids.map((id) => ({
      queryKey: ['evaluate', GAME_VERSION, version, id, includeUnlearned, includeTrivial, exits, choices[id]],
      queryFn: () =>
        call(
          client.POST('/api/evaluate', {
            ...GV,
            body: {
              recipe_id: id,
              include_unlearned: includeUnlearned,
              include_trivial: includeTrivial,
              exits,
              choices: choices[id] ?? {},
            },
          }),
        ),
      // Observers are matched by position, so only keep data that belongs to the same recipe.
      placeholderData: (previous: Evaluation | undefined, query?: { queryKey: readonly unknown[] }) =>
        query?.queryKey[3] === id ? previous : undefined,
    })),
    combine: (results) =>
      Object.fromEntries(
        results.map(({ data, isFetching, error }, i) => [ids[i], { data, isFetching, error }]),
      ),
  })
}

/** A recipe planned as a session: `copies` crafts at once in `city` (null: as the time settings pick), spelled
 * out with where to go. The user's plan `choices` apply. The previous plan stays shown while a new one loads. */
export function useSessionPlan(
  recipeId: number,
  { includeUnlearned, includeTrivial, exits, version }: EvaluateParams,
  choices: Choices | undefined,
  copies: number,
  city: string | null,
) {
  return useQuery({
    // under 'evaluate', so whatever re-costs plans (time settings, AH blocks) re-plans sessions too
    queryKey: ['evaluate', GAME_VERSION, version, recipeId, includeUnlearned, includeTrivial, exits, choices ?? {}, 'session', copies, city],
    queryFn: () =>
      call(
        client.POST('/api/evaluate', {
          ...GV,
          body: {
            recipe_id: recipeId,
            include_unlearned: includeUnlearned,
            include_trivial: includeTrivial,
            exits,
            choices: choices ?? {},
            copies,
            city: city ?? undefined,
          },
        }),
      ),
    placeholderData: keepPreviousData,
  })
}

/** How to sign in (never changes while the page is open). */
export function useConfig() {
  return useQuery({
    queryKey: ['config'],
    queryFn: () => call(client.GET('/api/config')),
    staleTime: Infinity,
  })
}

/** The signed-in user and tier; fetched once signed in (`enabled`), and again after linking. */
export function useMe(enabled: boolean) {
  return useQuery({
    queryKey: ['me'],
    queryFn: () => call(client.GET('/api/me')),
    enabled,
    staleTime: Infinity,
  })
}

/** Each realm's scans (every tier): where uploads are needed, and the realms one can browse. */
export function useCoverage() {
  const version = useDataVersion()
  return useQuery({
    queryKey: ['coverage', GAME_VERSION, version],
    queryFn: () => call(client.GET('/api/coverage', GV)),
  })
}

/** Your newest uploads, every game version. */
export function useUploads() {
  return useQuery({
    queryKey: ['uploads'],
    queryFn: () => call(client.GET('/api/uploads')),
  })
}

export type UploadKind = 'altarmy' | 'auctionator'

/** Import the Alt Army addon's export string (replaces your characters, like the file). */
export function usePasteUpload() {
  const invalidate = useInvalidateAll()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (text: string) => call(client.POST('/api/uploads/paste', { ...GV, body: { text } })),
    onSuccess: () => invalidate(),
    onError: () => queryClient.invalidateQueries({ queryKey: ['uploads'] }), // it lists rejected ones too
  })
}

/** Upload an addon file; everything it can change is refetched afterwards. */
export function useUpload() {
  const invalidate = useInvalidateAll()
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ kind, file }: { kind: UploadKind; file: File }) =>
      call(
        client.POST('/api/uploads', {
          ...GV,
          // The generated type says `string` (OpenAPI's binary format); the serializer sends the File itself.
          body: { kind, file: file as unknown as string, modified_at: file.lastModified, via: 'browser' },
          bodySerializer: (body) => {
            const form = new FormData()
            form.append('kind', body.kind)
            form.append('via', 'browser')
            if (body.modified_at != null) form.append('modified_at', String(body.modified_at))
            form.append('file', file, file.name)
            return form
          },
        }),
      ),
    onSuccess: () => invalidate(),
    onError: () => queryClient.invalidateQueries({ queryKey: ['uploads'] }), // it lists rejected ones too
  })
}

/** Your API keys for the CLI watcher. */
export function useApiKeys() {
  return useQuery({
    queryKey: ['keys'],
    queryFn: () => call(client.GET('/api/keys')),
  })
}

/** Make an API key; the response is the only time the key itself is shown. */
export function useCreateKey() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (label: string) => call(client.POST('/api/keys', { body: { label } })),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['keys'] }),
    onError: showError('Could not make a key'),
  })
}

export function useRevokeKey() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (keyId: number) => call(client.DELETE('/api/keys/{key_id}', { params: { path: { key_id: keyId } } })),
    onSuccess: (keys) => queryClient.setQueryData(['keys'], keys),
    onError: showError('Could not revoke the key'),
  })
}

export function useAuctionatorFiles() {
  return useQuery({
    queryKey: ['auctionator', GAME_VERSION, 'files'],
    queryFn: () => call(client.GET('/api/auctionator/files', GV)),
  })
}

export function useAltArmyFiles() {
  return useQuery({
    queryKey: ['altarmy', GAME_VERSION, 'files'],
    queryFn: () => call(client.GET('/api/altarmy/files', GV)),
  })
}

function showError(title: string) {
  return (error: Error) => notifications.show({ color: 'red', title, message: error.message })
}

/** Items never sold on the AH: searches only vendor or disenchant them. */
export function useAhBlocked() {
  return useQuery({
    queryKey: ['ah-blocked', GAME_VERSION],
    queryFn: () => call(client.GET('/api/ah-blocked', GV)),
  })
}

/** The user's time settings: where plans are timed, seconds per action, what an hour is worth. */
export function useTime() {
  return useQuery({
    queryKey: ['time', GAME_VERSION],
    queryFn: () => call(client.GET('/api/time', GV)),
  })
}

/** Save the city (null: the faction's default) and the settings that differ from the defaults; searches and
 * re-costed plans are refetched, since plans depend on them. */
export function useSetTime() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (body: { city: string | null; config: Partial<TimeConfig> }) =>
      call(client.PUT('/api/time', { ...GV, body: { city: body.city, config: body.config as Record<string, number> } })),
    onSuccess: (settings) => {
      queryClient.setQueryData(['time', GAME_VERSION], settings)
      return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] === 'rank' || q.queryKey[0] === 'evaluate' })
    },
    onError: showError('Could not save the time settings'),
  })
}

/** Never sell an item on the AH, or allow it again; searches and re-costed plans are refetched. */
export function useSetAhBlocked() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ itemId, blocked }: { itemId: number; blocked: boolean }) => {
      const params = { params: { path: { item_id: itemId }, query: { game_version: GAME_VERSION } } }
      return call(blocked ? client.PUT('/api/ah-blocked/{item_id}', params) : client.DELETE('/api/ah-blocked/{item_id}', params))
    },
    onSuccess: (list, { itemId, blocked }) => {
      queryClient.setQueryData(['ah-blocked', GAME_VERSION], list)
      if (blocked) {
        const name = list.details[itemId]?.name ?? `Item ${itemId}`
        notifications.show({
          title: `${name} won't be sold on the auction house`,
          message: 'Allow it again from its menu or the Manage page.',
        })
      }
      return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] === 'rank' || q.queryKey[0] === 'evaluate' })
    },
    onError: showError('Could not update the auction house list'),
  })
}

/** The user's favorite recipes: searches list them first. */
export function useFavorites() {
  return useQuery({
    queryKey: ['favorites', GAME_VERSION],
    queryFn: () => call(client.GET('/api/favorites', GV)),
  })
}

/** Mark a recipe as a favorite, or not; searches are refetched, since favorites come first. */
export function useSetFavorite() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ recipeId, favorite }: { recipeId: number; favorite: boolean }) => {
      const params = { params: { path: { recipe_id: recipeId }, query: { game_version: GAME_VERSION } } }
      return call(favorite ? client.PUT('/api/favorites/{recipe_id}', params) : client.DELETE('/api/favorites/{recipe_id}', params))
    },
    onSuccess: (list) => {
      queryClient.setQueryData(['favorites', GAME_VERSION], list)
      return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] === 'rank' })
    },
    onError: showError('Could not update your favorites'),
  })
}

/** Every mutation changes the database, so refetch everything afterwards. */
function useInvalidateAll() {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries()
}

function updateGameData(onlyIfNew: boolean) {
  return call(
    client.POST('/api/game-data/update', { params: { query: { game_version: GAME_VERSION, only_if_new: onlyIfNew } } }),
  )
}

function showUpdated(r: UpdateResult, title: string) {
  notifications.show({
    color: 'green',
    title,
    message: `Loaded build ${r.build}: ${r.items.toLocaleString()} items, ${r.recipes.toLocaleString()} recipes.`,
  })
}

export function useUpdateGameData() {
  const invalidate = useInvalidateAll()
  return useMutation({
    mutationFn: () => updateGameData(false),
    onSuccess: (r) => {
      showUpdated(r, 'Game data updated')
      return invalidate()
    },
    onError: showError('Update failed'),
  })
}

/**
 * Once per page load, fetch the game's newest build if the database does not have it yet. Failures only go to
 * the console: being offline should not raise a toast on every visit.
 */
export function useAutoUpdateGameData() {
  const invalidate = useInvalidateAll()
  const { mutate } = useMutation({
    mutationFn: () => updateGameData(true),
    onSuccess: (r) => {
      if (!r.updated) return
      showUpdated(r, 'New game data downloaded')
      return invalidate()
    },
    onError: (error) => console.warn('Automatic game data update failed:', error),
  })
  const started = useRef(false) // StrictMode runs effects twice in development
  useEffect(() => {
    if (started.current) return
    started.current = true
    mutate()
  }, [mutate])
}

/**
 * Toast whenever the server's addon sync re-imported Alt Army or Auctionator data: while the page is
 * open (status polling), or since it was last open.
 */
export function useSyncNotifications() {
  const status = useStatus().data
  useEffect(() => {
    if (!status) return
    const lines = importedSince(readSyncSeen(GAME_VERSION), status)
    writeSyncSeen(GAME_VERSION, syncSeen(status))
    if (lines.length) notifications.show({ color: 'green', title: 'Addon data imported', message: lines.join(' ') })
  }, [status])
}

/** The mutations below answer with the new status: show it at once, then refetch the rest. */
function useApplyStatus() {
  const queryClient = useQueryClient()
  return (status: Status) => {
    queryClient.setQueryData(['status', GAME_VERSION], status)
    return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] !== 'status' })
  }
}

/** Switch realm/faction; the server swaps in that realm's Auctionator prices. */
export function useSelectRealm() {
  const apply = useApplyStatus()
  return useMutation({
    mutationFn: (body: Selection) => call(client.PUT('/api/selection', { ...GV, body })),
    onSuccess: apply,
    onError: showError('Could not switch realm'),
  })
}

export function useSetSources() {
  const apply = useApplyStatus()
  return useMutation({
    mutationFn: (body: Sources) => call(client.PUT('/api/sources', { ...GV, body })),
    onSuccess: apply,
    onError: showError('Could not use that file'),
  })
}

/** Re-import both addon files even if they look unchanged. */
export function useSyncNow() {
  const apply = useApplyStatus()
  return useMutation({
    mutationFn: () => call(client.POST('/api/sync', GV)),
    onSuccess: apply,
    onError: showError('Sync failed'),
  })
}

export function useReload() {
  const invalidate = useInvalidateAll()
  return useMutation({
    mutationFn: () => call(client.POST('/api/reload', GV)),
    onSuccess: () => invalidate(),
    onError: showError('Reload failed'),
  })
}
