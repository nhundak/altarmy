// Start the Firebase Auth and Firestore emulators for `npm run dev` (its `dev:auth`), trying again when they never
// come up. Now and then the Firestore emulator's JVM opens its websocket port (9150) and then hangs before opening
// 8080: firebase-tools gives up after 60 s ("TIMEOUT: Port 8080 on 127.0.0.1 was not active within 60000ms") and
// exits, leaving that JVM behind. A fresh start works, so a failed attempt frees the emulators' ports
// (free-ports.mjs, which kills the leftover) and starts again, up to ATTEMPTS times. Once the emulators are ready,
// an exit is passed on as it is.
import { spawn, spawnSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ATTEMPTS = 3
const PORTS = ['9099', '8080', '9150', '4400', '4500'] // auth, firestore, its websocket, the hub, logging
const READY = 'All emulators ready'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const firebase = join(root, 'node_modules', 'firebase-tools', 'lib', 'bin', 'firebase.js')
const args = [firebase, 'emulators:start', '--only', 'auth,firestore', '--project', 'demo-altarmy']

function freePorts() {
  spawnSync(process.execPath, [join(root, 'scripts', 'free-ports.mjs'), ...PORTS], { cwd: root, stdio: 'inherit' })
}

/** One run of the emulators; resolves to its exit code and whether they got ready. */
function start() {
  return new Promise((resolve) => {
    let ready = false
    const child = spawn(process.execPath, args, { cwd: root, stdio: ['inherit', 'pipe', 'inherit'] })
    child.stdout.on('data', (data) => {
      process.stdout.write(data)
      if (!ready && data.toString().includes(READY)) ready = true
    })
    child.on('exit', (code) => resolve({ code: code ?? 1, ready }))
  })
}

for (let attempt = 1; ; attempt++) {
  const { code, ready } = await start()
  if (ready || code === 0 || attempt === ATTEMPTS) process.exit(code)
  console.error(`dev-auth: the emulators did not start (exit ${code}); trying again (${attempt + 1}/${ATTEMPTS})`)
  freePorts()
}
