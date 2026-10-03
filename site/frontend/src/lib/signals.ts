import type { Firestore } from 'firebase/firestore'
import { firebaseApp } from './auth'

/**
 * Price signals: the server writes `priceSignals/<auction house id>` in Firestore whenever that auction house's
 * prices change, holding only its price version (never prices). Listening to it tells the app to refetch at once
 * instead of waiting for the status poll. The Firestore SDK is loaded on first use, so it stays out of the main
 * bundle.
 */
const COLLECTION = 'priceSignals'

let firestore: Promise<Firestore> | null = null

function getDb(): Promise<Firestore> | null {
  const started = firebaseApp()
  if (!started) return null
  firestore ??= import('firebase/firestore').then((fs) => {
    const db = fs.getFirestore(started.app)
    const host = started.config.firestore_emulator_host
    if (host) {
      const [name, port] = host.split(':')
      fs.connectFirestoreEmulator(db, name ?? '127.0.0.1', Number(port))
    }
    return db
  })
  return firestore
}

/**
 * Call `onVersion` with the auction house's price version now and whenever the server bumps it. Returns the
 * unsubscribe. Does nothing before Firebase started (tests, or signing in failed): the status poll still catches up.
 */
export function watchPriceSignal(auctionHouseId: number, onVersion: (version: number) => void): () => void {
  const db = getDb()
  if (!db) return () => {}
  let stop: (() => void) | null = null
  let cancelled = false
  void Promise.all([db, import('firebase/firestore')])
    .then(([d, fs]) => {
      if (cancelled) return
      stop = fs.onSnapshot(
        fs.doc(d, COLLECTION, String(auctionHouseId)),
        (snap) => {
          const version: unknown = snap.get('version')
          if (typeof version === 'number') onVersion(version)
        },
        // a denied or failed listen is only a missed nudge
        () => {},
      )
    })
    .catch(() => {})
  return () => {
    cancelled = true
    stop?.()
  }
}
