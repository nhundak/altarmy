// Start the Python API for `npm run dev` (`altarmy-profit serve` on :8600) using the project venv's interpreter
// (Windows or POSIX layout). It signs users in against the Firebase Auth emulator (`npm run dev:auth`, project
// demo-altarmy), or with `--prod-auth` (npm run dev:prod-auth) against the real project in hosted.env. The
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

const EMULATOR = { FIREBASE_PROJECT_ID: 'demo-altarmy', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }

const args = process.argv.slice(2)
const prodAuth = args.includes('--prod-auth')
const env = { ...process.env, ...(prodAuth ? readEnvFile(join(root, 'hosted.env')) : EMULATOR) }
if (prodAuth) delete env.FIREBASE_AUTH_EMULATOR_HOST
const child = spawn(python, ['-m', 'altarmy_profit.cli', 'serve', ...args.filter((a) => a !== '--prod-auth')], {
  cwd: root,
  stdio: 'inherit',
  env,
})
child.on('exit', (code) => process.exit(code ?? 0))
