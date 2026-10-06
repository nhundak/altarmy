// Start the Python API for `npm run dev` (`altarmy-profit serve` on :8600) using the project venv's interpreter
// (Windows or POSIX layout). It signs users in against the Firebase Auth emulator and sends price signals to the
// Firestore emulator (`npm run dev:auth`, project demo-altarmy), or with `--staging-auth` (npm run dev:staging-auth) against the staging project in staging.env. The
// database is DATABASE_URL, else data/altarmy-profit.sqlite, migrated on start. Once the API answers, it loads
// each version's pinned build in the background (`altarmy-profit ingest --only-if-new`: nothing to do unless
// data/game-data.json, the ingest code or its CSVs moved, e.g. after pulling a game-data commit), unless
// `--no-ingest`, then runs the merge (`altarmy-profit merge`: the 7-day price statistics of the scans uploaded
// so far), unless `--no-prices`; a failure is only reported. Prices themselves come from uploads: scan with
// the Alt Army addon and upload AltArmy_TBC.lua. The API restarts whenever src/altarmy_profit changes (`serve
// --reload`; `--no-reload` to keep one process), losing its in-memory market and rank caches.
import { spawn } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const python = [join(root, '.venv', 'Scripts', 'python.exe'), join(root, '.venv', 'bin', 'python')].find(existsSync)
if (!python) {
  console.error('No .venv found: python -m venv .venv, then .venv\Scripts\python -m pip install -e ".[dev,ui]"')
  process.exit(1)
}

/** KEY=VALUE lines of an env file; blank lines and # comments are skipped. */
function readEnvFile(path) {
  const env = {}
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)
    if (m) env[m[1]] = m[2]
  }
  return env
}

const EMULATOR = {
  FIREBASE_PROJECT_ID: 'demo-altarmy',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', // price signals
}
// Against staging's Firebase project, a local database's auction house ids are not staging's: send no signals.
const STAGING = { PRICE_SIGNALS: 'off' }

const args = process.argv.slice(2)
const stagingAuth = args.includes('--staging-auth')
const fetchPrices = !args.includes('--no-prices')
const loadGameData = !args.includes('--no-ingest')
const env = { ...process.env, ...(stagingAuth ? { ...readEnvFile(join(root, 'staging.env')), ...STAGING } : EMULATOR) }
if (stagingAuth) {
  delete env.FIREBASE_AUTH_EMULATOR_HOST
  delete env.FIRESTORE_EMULATOR_HOST
}
const API = 'http://127.0.0.1:8600/api/config'

/** Whether an API answers on :8600. */
async function answers() {
  try {
    return (await fetch(API)).ok
  } catch {
    return false // not listening (yet)
  }
}

// Another API already on :8600 would answer for ours, which then fails to bind: run no jobs for it.
const portTaken = await answers()
const ownArgs = ['--staging-auth', '--no-prices', '--no-ingest', '--no-reload']
const reload = args.includes('--no-reload') ? [] : ['--reload']
const serveArgs = ['serve', ...reload, ...args.filter((a) => !ownArgs.includes(a))]
const child = spawn(python, ['-m', 'altarmy_profit.cli', ...serveArgs], {
  cwd: root,
  stdio: 'inherit',
  env,
})
let exited = false
let job = null // the background job running, stopped with the API
child.on('exit', (code) => {
  exited = true
  job?.kill()
  process.exit(code ?? 0)
})

/** Runs `altarmy-profit <args>` with the API's environment; resolves to its exit code. */
function cli(...cliArgs) {
  return new Promise((resolve) => {
    job = spawn(python, ['-m', 'altarmy_profit.cli', ...cliArgs], { cwd: root, stdio: 'inherit', env })
    job.on('error', () => resolve(1))
    job.on('exit', (code) => {
      job = null
      resolve(code ?? 1)
    })
  })
}

/** Resolves once our API answers (so it has migrated the database), or false if it exits first. */
async function apiReady() {
  while (!exited) {
    if (await answers()) return !exited
    await new Promise((r) => setTimeout(r, 500))
  }
  return false
}

if (portTaken) {
  console.log('dev-api: something already answers on :8600; not loading game data or merging prices')
} else if ((loadGameData || fetchPrices) && (await apiReady())) {
  for (const version of loadGameData ? ['forever', 'tbc'] : []) {
    if (exited) break
    console.log(`dev-api: loading ${version}'s pinned game data if it moved (--no-ingest to skip)`)
    if ((await cli('--game-version', version, 'ingest', '--only-if-new')) !== 0 && !exited) {
      console.log(`dev-api: the ${version} ingest failed (see above); the API keeps running`)
    }
  }
}
if (!portTaken && fetchPrices && !exited) {
  console.log('dev-api: merging price statistics (--no-prices to skip)')
  const merged = await cli('merge')
  if (!exited) {
    console.log(
      merged === 0
        ? 'dev-api: price statistics are up to date'
        : 'dev-api: the merge failed (see above); the API keeps running',
    )
  }
}
