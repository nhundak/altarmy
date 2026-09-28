// Start the Python API for `npm run dev` (`altarmy-profit serve` on :8600) using the project venv's interpreter
// (Windows or POSIX layout). It signs users in against the Firebase Auth emulator and sends price signals to the
// Firestore emulator (`npm run dev:auth`, project demo-altarmy), or with `--staging-auth` (npm run dev:staging-auth) against the staging project in staging.env. The
// database is DATABASE_URL, else data/altarmy-profit.sqlite, migrated on start. Once the API answers, it fetches
// AHledger's newest prices and merges them (`altarmy-profit ahledger`, then `merge`) in the background, unless
// `--no-prices`; a failure (offline, say) is only reported.
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

// Another API already on :8600 would answer for ours, which then fails to bind: fetch no prices for it.
const portTaken = await answers()
const ownArgs = ['--staging-auth', '--no-prices']
const child = spawn(python, ['-m', 'altarmy_profit.cli', 'serve', ...args.filter((a) => !ownArgs.includes(a))], {
  cwd: root,
  stdio: 'inherit',
  env,
})
let exited = false
let job = null // the price job running, stopped with the API
child.on('exit', (code) => {
  exited = true
  job?.kill()
  process.exit(code ?? 0)
})

/** Runs `altarmy-profit <command>` with the API's environment; resolves to its exit code. */
function cli(command) {
  return new Promise((resolve) => {
    job = spawn(python, ['-m', 'altarmy_profit.cli', command], { cwd: root, stdio: 'inherit', env })
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
  console.log('dev-api: something already answers on :8600; fetching no AHledger prices')
} else if (fetchPrices && (await apiReady())) {
  console.log('dev-api: fetching AHledger prices (--no-prices to skip)')
  const ahledger = await cli('ahledger')
  const merged = exited ? 1 : await cli('merge')
  if (!exited) {
    console.log(
      ahledger === 0 && merged === 0
        ? 'dev-api: AHledger prices are up to date'
        : 'dev-api: the AHledger price update failed (see above); the API keeps running',
    )
  }
}
