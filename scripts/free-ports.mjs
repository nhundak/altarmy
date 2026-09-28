// Free the dev servers' ports before `npm run dev` (its `predev` hook): kills whatever still listens on the TCP ports
// given as arguments, such as an emulator or API left running by an earlier session that did not shut down cleanly.
// Windows (netstat, taskkill with the process tree) or POSIX (lsof, kill).
import { execFileSync } from 'node:child_process'

const ports = process.argv.slice(2).map(Number)
const windows = process.platform === 'win32'

function run(cmd, args) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
  } catch (e) {
    return e.stdout ?? '' // lsof exits 1 when nothing matches
  }
}

/** PIDs listening on each port, as a Map of pid -> ports. */
function listeners() {
  const found = new Map()
  const add = (pid, port) => pid > 0 && found.set(pid, [...(found.get(pid) ?? []), port])
  if (windows) {
    for (const line of run('netstat', ['-ano']).split(/\r?\n/)) {
      const cols = line.trim().split(/\s+/)
      if (cols[0] !== 'TCP' || cols[3] !== 'LISTENING') continue
      const port = Number(cols[1].slice(cols[1].lastIndexOf(':') + 1))
      if (ports.includes(port)) add(Number(cols[4]), port)
    }
  } else {
    for (const port of ports) {
      for (const pid of run('lsof', ['-nP', `-iTCP:${port}`, '-sTCP:LISTEN', '-t']).split(/\s+/)) {
        if (pid) add(Number(pid), port)
      }
    }
  }
  return found
}

function name(pid) {
  const out = windows
    ? run('tasklist', ['/FI', `PID eq ${pid}`, '/FO', 'CSV', '/NH']).split(',')[0]
    : run('ps', ['-p', String(pid), '-o', 'comm='])
  return out.replace(/"/g, '').trim() || '?'
}

const busy = listeners()
for (const [pid, on] of busy) {
  if (pid === process.pid) continue
  console.log(`free-ports: killing ${name(pid)} (pid ${pid}) on :${[...new Set(on)].join(', :')}`)
  if (windows) run('taskkill', ['/F', '/T', '/PID', String(pid)])
  else {
    try {
      process.kill(pid, 'SIGKILL')
    } catch {
      // already gone
    }
  }
}

// The OS can take a moment to release the sockets.
for (let i = 0; busy.size && i < 50 && listeners().size; i++) {
  await new Promise((r) => setTimeout(r, 100))
}
const left = listeners()
if (left.size) {
  console.error(`free-ports: still in use: :${[...left.values()].flat().join(', :')}`)
  process.exit(1)
}
