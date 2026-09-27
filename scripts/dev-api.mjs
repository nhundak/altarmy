// Start the Python API for `npm run dev` (`altarmy-profit serve` on :8600) using the project venv's interpreter
// (Windows or POSIX layout). It signs users in against the Firebase Auth emulator and sends price signals to the
// Firestore emulator (`npm run dev:auth`, project demo-altarmy), or with `--staging-auth` (npm run dev:staging-auth) against the staging project in staging.env. The
// database is DATABASE_URL, else data/altarmy-profit.sqlite, migrated on start.
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
const env = { ...process.env, ...(stagingAuth ? { ...readEnvFile(join(root, 'staging.env')), ...STAGING } : EMULATOR) }
if (stagingAuth) {
  delete env.FIREBASE_AUTH_EMULATOR_HOST
  delete env.FIRESTORE_EMULATOR_HOST
}
const child = spawn(python, ['-m', 'altarmy_profit.cli', 'serve', ...args.filter((a) => a !== '--staging-auth')], {
  cwd: root,
  stdio: 'inherit',
  env,
})
child.on('exit', (code) => process.exit(code ?? 0))
