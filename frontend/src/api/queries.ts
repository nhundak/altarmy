import { useDebouncedCallback } from '@mantine/hooks'
import { notifications } from '@mantine/notifications'
import { keepPreviousData, useMutation, useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  call,
  client,
  type Evaluation,
  type Selection,
  type Status,
  type TimeConfig,
  type TimeSettings,
} from './client'
import { GAME_VERSION } from '../lib/gameVersion'
import type { Choices } from '../lib/choices'

/** The `game_version` query parameter every per-game route takes. */
const GV = { params: { query: { game_version: GAME_VERSION } } }

/**
 * The server status. Polled, and refetched when the user comes back from the game, so the watcher's uploads
 * show up; new prices refetch it at once (`PriceSignal`).
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
 * Part of the keys of data that imports and merges affect: the user's data version (bumped whenever an upload or edit
 * changed something) and the selected auction house's price version (bumped whenever its prices changed).
 */
export function useDataVersion() {
  const status = useStatus().data
  return status && `${status.data_version}.${status.price_version ?? 0}`
}

/** The selected auction house's price version, sent with requests that price things: after a price signal the
 * server then never answers from a market older than it (`MarketCache.get`). */
function usePriceVersion() {
  return useStatus().data?.price_version ?? undefined
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

/** Every profession that has recipes in this game version, by name (game data: it changes only with an update). */
export function useProfessions() {
  return useQuery({
    queryKey: ['professions', GAME_VERSION],
    queryFn: () => call(client.GET('/api/professions', GV)),
    staleTime: Infinity,
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

/** A way to sell; `skill` is an enchant's: cast for the skill point alone, nothing is sold. */
export type Exit = 'vendor' | 'disenchant' | 'ah' | 'skill'

/** Which recipes nobody has learned count: none, those a character can train (see `lookAhead` and `sources`), or
 * every recipe of their professions. */
export type Unlearned = 'none' | 'train' | 'all'

/** What teaches a recipe: a profession trainer, a recipe item that can be traded, or only ones that bind on pickup. */
export type Source = 'trainer' | 'recipe' | 'bop'
export const ALL_SOURCES: readonly Source[] = ['trainer', 'recipe', 'bop']
/** The most skill a recipe to train may need beyond what the character has (the API's limit). */
export const MAX_LOOK_AHEAD = 50

/** `/api/rank` parameters: money in copper, ROI as a fraction (0.5 = 50%), `null` for no bound. */
export type RankParams = {
  unlearned: Unlearned
  /** recipes to train: how much more skill than a character has one may need (0: what they can train now) */
  lookAhead: number
  /** recipes to train: what may teach them */
  sources: Source[]
  /** false: only recipes that can give the crafter a skillup */
  includeTrivial: boolean
  /** the characters being skilled up: only they do the final craft, the lowest-skilled first; empty for anyone */
  skillCrafters: string[]
  exits: Exit[]
  /** disenchant at an Arcane Salvager: a 10% chance of a second disenchant's materials */
  arcaneSalvager: boolean
  minCost: number | null
  maxCost: number | null
  minProfit: number | null
  maxProfit: number | null
  minRoi: number | null
  maxRoi: number | null
  /** only recipes of these professions; empty for every one */
  professions: string[]
  /** best profit per session first, per hour of play, or cheapest expected skill point */
  sort: 'profit' | 'rate' | 'skill'
  top: number
}

const orUndefined = <T>(v: T | null) => v ?? undefined

/** The look-ahead and sources as the API takes them: only recipes to train have any. */
const training = ({
  unlearned,
  lookAhead,
  sources,
}: Pick<RankParams, 'unlearned' | 'lookAhead' | 'sources'>): { look_ahead?: number; sources?: Source[] } =>
  unlearned === 'train' ? { look_ahead: lookAhead, sources } : {}

/** Ranked recipes for the selected realm/faction's characters (every recipe without characters). */
export function useRank(params: RankParams) {
  const version = useDataVersion()
  const priceVersion = usePriceVersion()
  return useQuery({
    queryKey: ['rank', GAME_VERSION, version, params],
    queryFn: () =>
      call(
        client.GET('/api/rank', {
          params: {
            query: {
              game_version: GAME_VERSION,
              unlearned: params.unlearned,
              ...training(params),
              include_trivial: params.includeTrivial,
              skill_crafters: params.skillCrafters.length ? params.skillCrafters : undefined,
              exits: params.exits,
              arcane_salvager: params.arcaneSalvager,
              min_cost: orUndefined(params.minCost),
              max_cost: orUndefined(params.maxCost),
              min_profit: orUndefined(params.minProfit),
              max_profit: orUndefined(params.maxProfit),
              min_roi: orUndefined(params.minRoi),
              max_roi: orUndefined(params.maxRoi),
              professions: params.professions.length ? params.professions : undefined,
              sort: params.sort === 'profit' ? undefined : params.sort,
              top: params.top,
              price_version: priceVersion,
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
export type EvaluateParams = Pick<
  RankParams,
  'unlearned' | 'lookAhead' | 'sources' | 'includeTrivial' | 'skillCrafters' | 'exits' | 'arcaneSalvager'
> & { version?: string }

export type EvaluationState = { data?: Evaluation; isFetching: boolean; error: Error | null }

/** Each recipe re-costed with the user's choices, by recipe id. While a new choice loads, the recipe's
 * previous evaluation stays in `data`. */
export function useEvaluations(
  choices: Readonly<Record<number, Choices>>,
  { unlearned, lookAhead, sources, includeTrivial, skillCrafters, exits, arcaneSalvager, version }: EvaluateParams,
): Readonly<Record<number, EvaluationState>> {
  const ids = Object.keys(choices).map(Number)
  const priceVersion = usePriceVersion()
  return useQueries({
    queries: ids.map((id) => ({
      queryKey: ['evaluate', GAME_VERSION, version, id, unlearned, lookAhead, sources, includeTrivial, skillCrafters, exits, arcaneSalvager, choices[id]],
      queryFn: () =>
        call(
          client.POST('/api/evaluate', {
            ...GV,
            body: {
              recipe_id: id,
              unlearned,
              look_ahead: lookAhead,
              sources,
              include_trivial: includeTrivial,
              skill_crafters: skillCrafters,
              exits,
              arcane_salvager: arcaneSalvager,
              choices: choices[id] ?? {},
              price_version: priceVersion,
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

/** A recipe planned as a session of `copies` crafts (null: the time settings' batch, as ranked) in `city` (null: as
 * the time settings pick) with `crafter` doing the final craft (null: as ranked), spelled out with where to go. The
 * user's plan `choices` apply. Only fetched while `enabled`: with none set the ranked (or re-costed) result already
 * is this plan. The previous plan stays
 * shown while a new one loads. */
export function useSessionPlan(
  recipeId: number,
  { unlearned, lookAhead, sources, includeTrivial, skillCrafters, exits, arcaneSalvager, version }: EvaluateParams,
  choices: Choices | undefined,
  copies: number | null,
  city: string | null,
  crafter: string | null,
  enabled: boolean,
) {
  const priceVersion = usePriceVersion()
  return useQuery({
    // under 'evaluate', so whatever re-costs plans (time settings, AH blocks) re-plans sessions too
    queryKey: ['evaluate', GAME_VERSION, version, recipeId, unlearned, lookAhead, sources, includeTrivial, skillCrafters, exits, arcaneSalvager, choices ?? {}, 'session', copies, city, crafter],
    queryFn: () =>
      call(
        client.POST('/api/evaluate', {
          ...GV,
          body: {
            recipe_id: recipeId,
            unlearned,
            look_ahead: lookAhead,
            sources,
            include_trivial: includeTrivial,
            skill_crafters: skillCrafters,
            exits,
            arcane_salvager: arcaneSalvager,
            choices: choices ?? {},
            copies: copies ?? undefined,
            city: city ?? undefined,
            crafter: crafter ?? undefined,
            price_version: priceVersion,
          },
        }),
      ),
    placeholderData: keepPreviousData,
    enabled,
  })
}

/** Keep retrying a query the app can't do without (signing in), backing off to every 30 s. */
export const KEEP_TRYING = { retry: true, retryDelay: (attempt: number) => Math.min(1000 * 2 ** attempt, 30_000) }

/** How to sign in (never changes while the page is open). */
export function useConfig() {
  return useQuery({
    queryKey: ['config'],
    queryFn: () => call(client.GET('/api/config')),
    staleTime: Infinity,
    ...KEEP_TRYING,
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

/** The ingestion log and statistics for site admins (`enabled` only for them); polled like the status. */
export function useAdminIngestion(enabled: boolean) {
  return useQuery({
    queryKey: ['admin-ingestion', GAME_VERSION],
    queryFn: () => call(client.GET('/api/admin/ingestion', GV)),
    enabled,
    refetchInterval: 30_000,
    refetchOnWindowFocus: true,
  })
}

/** Start the game data ingest now (admins): the newest build, unless it is loaded already. */
export function useRunIngest() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => call(client.POST('/api/admin/jobs/ingest', GV)),
    onSuccess: (started) => {
      notifications.show({ color: 'green', title: 'Ingest started', message: started.detail })
      return queryClient.invalidateQueries({ queryKey: ['admin-ingestion'] })
    },
    onError: showError('Could not start the ingest'),
  })
}

/** Each realm's scans (every tier): the realms one can browse, and how fresh their prices are. */
export function useCoverage() {
  const version = useDataVersion()
  return useQuery({
    queryKey: ['coverage', GAME_VERSION, version],
    queryFn: () => call(client.GET('/api/coverage', GV)),
  })
}

export type UploadKind = 'altarmy' | 'auctionator'

/** Upload the Alt Army addon's export string (replaces your characters, like the file). */
export function usePasteUpload() {
  const invalidate = useInvalidateAll()
  return useMutation({
    mutationFn: (text: string) => call(client.POST('/api/uploads/paste', { ...GV, body: { text } })),
    onSuccess: () => invalidate(),
  })
}

/** Upload an addon file; everything it can change is refetched afterwards. */
export function useUpload() {
  const invalidate = useInvalidateAll()
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
const TIME_KEY = ['time', GAME_VERSION]

export function useTime() {
  return useQuery({
    queryKey: TIME_KEY,
    queryFn: () => call(client.GET('/api/time', GV)),
    // Changes only through `useSetTime` (which stores the answer) or a new selection (which refetches everything).
    staleTime: Infinity,
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
      // The cached city and config are what the user has edited since (`useEditTime`), so never older than the answer.
      queryClient.setQueryData<TimeSettings>(TIME_KEY, (shown) =>
        shown ? { ...settings, city: shown.city, config: shown.config } : settings,
      )
      return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] === 'rank' || q.queryKey[0] === 'evaluate' })
    },
    onError: showError('Could not save the time settings'),
  })
}

/** The config's settings that differ from the defaults: what is saved. */
function changes(config: TimeConfig, defaults: TimeConfig): Partial<TimeConfig> {
  return Object.fromEntries(
    Object.entries(config).filter(([key, value]) => value !== defaults[key as keyof TimeConfig]),
  ) as Partial<TimeConfig>
}

/**
 * Edit the time settings. The cached settings are the draft every editor shares (the options' Crafts per session and
 * the Time assumptions panel): an edit shows at once, and a moment after the last one the settings are saved as the
 * cache then holds them, so one editor never undoes another's change.
 */
export function useEditTime() {
  const queryClient = useQueryClient()
  const setTime = useSetTime()
  const save = useDebouncedCallback(() => {
    const shown = queryClient.getQueryData<TimeSettings>(TIME_KEY)
    if (shown) setTime.mutate({ city: shown.city, config: changes(shown.config, shown.defaults) })
  }, 600)
  const edit = (next: { city: string | null; config: TimeConfig }) => {
    queryClient.setQueryData<TimeSettings>(TIME_KEY, (shown) => shown && { ...shown, ...next })
    save()
  }
  return { edit, saving: setTime.isPending }
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

/** The mutations below answer with the new status: show it at once, then refetch the rest. */
function useApplyStatus() {
  const queryClient = useQueryClient()
  return (status: Status) => {
    queryClient.setQueryData(['status', GAME_VERSION], status)
    return queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] !== 'status' })
  }
}

/** Switch realm/faction: whose recipes count, and which auction house prices them. */
export function useSelectRealm() {
  const apply = useApplyStatus()
  return useMutation({
    mutationFn: (body: Selection) => call(client.PUT('/api/selection', { ...GV, body })),
    onSuccess: apply,
    onError: showError('Could not switch realm'),
  })
}

