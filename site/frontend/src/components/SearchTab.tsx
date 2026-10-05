import { useState } from 'react'
import { Alert, Loader, Select, Stack } from '@mantine/core'
import { useCharacters, useCoverage, useProfessions, useSelectRealm, useStatus, useTrack } from '../api/queries'
import { fromKey, realmOptions, toKey } from '../lib/realms'
import { useSession } from '../lib/session'
import {
  answer,
  hasEnchanter,
  nextStep,
  presetsFor,
  professionsOf,
  setupSchema,
  storePresets,
  type Setup as SetupAnswers,
  type Step,
} from '../lib/setup'
import { useStoredState } from '../lib/storage'
import { AimSearch } from './AimSearch'
import { HOW_TO_SCAN } from './PriceFreshness'
import { PriceSignal } from './PriceSignal'
import { RealmCard } from './RealmCard'
import { Setup } from './Setup'

export { SHOW_ARCANE_SALVAGER } from './AimSearch'

const storedSetup = setupSchema.nullable()

/**
 * The search: first the setup's questions (what the user is after, then a profession, or how to sell), then the realm
 * card (realm and faction, price freshness, an upload in place) and, with a realm, the aim's own search (`AimSearch`:
 * its options, advanced filters and ranked recipes). The answers decide the ranking's order and preset the filters
 * they are about; they are remembered per user, like the Profit page's start.
 */
export function SearchTab() {
  const { uid } = useSession()
  const status = useStatus()
  const characters = useCharacters()
  const coverage = useCoverage()
  const select = useSelectRealm()
  const professionNames = useProfessions().data
  const [setup, setSetup] = useStoredState<SetupAnswers | null>(`altarmy-profit.setup.${uid}`, storedSetup, null)
  // Skilling up needs the characters' professions: without imported characters it can't be picked (and a saved
  // setup asks again).
  const noCharacters = characters.data !== undefined && characters.data.groups.length === 0
  // A question the user reopened from the summary; otherwise the first unanswered one is shown.
  const [editing, setEditing] = useState<Step | null>(null)
  const groups = characters.data?.groups ?? []
  // Show the realm being switched to while the server imports its prices.
  const selection = select.isPending ? select.variables : status.data?.selection
  const group = groups.find((g) => selection && toKey(g) === toKey(selection))
  const professions = professionsOf(group, professionNames)
  const [picks, setPicks] = useState(0)
  const track = useTrack()
  // Asks from the search to upload a scan (making gold's no-scan notice), each opening the realm card's upload.
  const [uploadAsked, setUploadAsked] = useState(0)

  /** Answer one question, writing the filters that answer presets (the user may change them afterwards). */
  const pick = (step: Step, value: string, characters?: string[]) => {
    const next = answer(setup, step, value, characters)
    setSetup(next)
    // skilling up always asks which profession, even when an answer is kept from before; making gold asks nothing more
    setEditing(step === 'aim' && next.aim === 'skill' ? 'profession' : null)
    setPicks((n) => n + 1)
    if (step === 'aim') track('aim_chosen', { aim: next.aim })
    // The aim's search is not mounted while a question is open: it starts from these once the setup is complete.
    storePresets(next.aim, presetsFor(next, step))
  }

  if (status.isPending || characters.isPending) return <Loader />
  if (status.isError) return <Alert color="red">{status.error.message}</Alert>
  if (status.data.recipes === 0) {
    return (
      <Alert color="red">
        No game data has been loaded yet. If you run this site, run `altarmy-profit ingest`.
      </Alert>
    )
  }

  // Without characters on the selected realm, every recipe is ranked for one unnamed crafter.
  const browsing = group === undefined
  const noEnchanter = !!selection && !browsing && !hasEnchanter(group)
  const options = realmOptions(groups, coverage.data ?? [])
  // The characters' realms come first, without a heading; the other priced realms under Browse a realm.
  const item = ({ value, label }: { value: string; label: string }) => ({ value, label })
  const browse = options.filter((o) => o.section === 'Browse a realm').map(item)
  if (selection && !options.some((o) => o.value === toKey(selection))) {
    // e.g. a realm whose scan is still being merged: still show what is selected
    browse.push({ value: toKey(selection), label: selection.realm })
  }
  const realmData = [
    ...options.filter((o) => o.section === 'Your characters').map(item),
    ...(browse.length > 0 ? [{ group: 'Browse a realm', items: browse }] : []),
  ]
  // The selection's auction house and its newest scan; undefined while the coverage is still loading.
  const house = coverage.data?.find((c) => c.auction_house_id === status.data.auction_house_id)
  const lastScan = coverage.data && status.data.auction_house_id !== null ? (house?.last_scan ?? null) : undefined
  const step = editing ?? nextStep(setup, professions, noCharacters)
  // In the realm card the picker has no visible label (it sits beside the upload buttons), only its accessible name.
  const realmSelect = (inCard = false) => (
    <Select
      label={inCard ? undefined : 'Realm'}
      aria-label={inCard ? 'Realm' : undefined}
      placeholder="No realm has prices yet"
      data={realmData}
      value={selection ? toKey(selection) : null}
      onChange={(key) => key && select.mutate(fromKey(key))}
      allowDeselect={false}
      size={inCard ? 'sm' : undefined}
      w={inCard ? 300 : undefined}
      maw={inCard ? '100%' : 420}
    />
  )

  return (
    <Stack>
      <PriceSignal />
      <Setup
        setup={setup}
        step={step}
        professions={professions}
        onPick={pick}
        onOpen={setEditing}
        unavailable={noCharacters ? { skill: 'Upload your characters first, so we know which skills they have.' } : {}}
      >
        {/* Which professions there are depends on the realm: it can be changed right there. */}
        {step === 'profession' && realmSelect()}
      </Setup>
      {step === null && (
        <>
          <RealmCard
            select={realmSelect(true)}
            lastScan={selection ? lastScan : undefined}
            uploadAsked={uploadAsked}
          />
          {selection && setup ? (
            <AimSearch
              key={setup.aim}
              setup={setup}
              professions={professions}
              browsing={browsing}
              noEnchanter={noEnchanter}
              realm={selection.realm}
              noPrices={status.data.prices === 0}
              salvagerDefault={characters.data?.arcane_salvager ?? false}
              flush={characters.data ? picks : -1}
              onUpload={() => setUploadAsked((n) => n + 1)}
              lastScan={lastScan}
              watchedHours={house?.watched_hours}
              houseId={status.data.auction_house_id}
            />
          ) : (
            status.data.prices === 0 && <Alert color="yellow">No prices yet for this realm. {HOW_TO_SCAN}</Alert>
          )}
        </>
      )}
    </Stack>
  )
}
