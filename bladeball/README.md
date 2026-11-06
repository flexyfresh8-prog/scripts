# Blade Ball — BYAKUGAN RS26.7 (Audi RS × iOS 26 Fluid)

Mobile auto-parry for **Roblox Blade Ball**, built for **Delta iOS**.
The original **RS HUD** is back — Tango Red / Carbon Audi look — rebuilt with
iOS 26 liquid-glass motion: spring bounces, elastic pops, fluid steppers,
parry shockwaves, a Dynamic Island and an animated boot sequence.

**v26.7 — ANTI-DOUBLE-PARRY (fix):**
- the trigger could fire a **second packet on the same approach**: the speed
  cooldown is only `0.14 s` on fast balls, but the server's "ball parried
  away" redirect takes `1–2 × ping` (0.1–0.3 s) to reach your client — until
  it arrives the ball still reads as incoming and targeting you, so the TTI
  branch (which had **no per-approach cap**) or PANIC fired again. The wasted
  packet started the game's parry cooldown right before the real contact →
  dead
- **TTI now fires once per approach** — a refire needs the ball state to
  actually change (redirect / curve / new target / spam shot in between);
  a stale incoming ball can no longer re-trigger it
- post-fire lockout now covers replication: `max(cooldown, 2 × ping + 0.06)`
  — PANIC opens only after the redirect had its chance to arrive. A true
  miss still gets the last-chance refire (retries ≤ 4 unchanged); a saved
  approach stays silent
- lockout ping is the **worst case** of Data Ping and GetNetworkPing —
  Data Ping can read 0 for the first frames (or be missing on an executor),
  which silently shrank the lockout back to the `0.14 s` fast-ball cooldown
  and let the double return
- auto-spam shots also arm the gate, so the TTI branch can't stack a wasted
  packet on top of an engagement that is already firing

**v26.6 — PREDICT PARRY (new):**
- new **PREDICT** stepper on the panel: `OFF · 25% · 50% · 75% · 100%`
- when on, the trigger measures a **predicted future ball position** instead
  of the real one — lead = `PREDICT% × parry offset`, extrapolated with the
  same second-order curve model as the yellow server dot (follows curved
  flight)
- fires **earlier by design** — for high ping or very fast balls where the
  default window still feels a touch late; the island status shows
  `PREDICT PARRY` so you can see it engaging
- the fire window is **untouched** (pure send lead) — the predict lead lives
  on the measurement side only, so the v26.4 double-count can never come back
- **default OFF** — timing unchanged until you dial it in; start at 25–50%

**v26.5.1 — OBFUSCATION REMOVED (plain build):**
- the protected/obfuscated builds kept dying silently on Delta — the wrapper
  pill stuck at `booting…` while the encrypted body never ran, so there was
  nothing to debug
- **both links now serve the identical plain, readable build** — the same
  engine, the same v26.5 boot failsafe, just no mangling/encryption in the
  way. If anything fails, the tracer pill prints the exact stage and the
  Delta console shows the real Lua error
- protection will come back only in a form that provably runs on Delta

**v26.5 — BOOT FAILSAFE ("never gets past booting" — fixed):**
- the `getgc` PRY scan **never yielded** — on a long-running server the heap
  is huge and the scan used to hog the VM for 30+ s, freezing the boot card,
  the tracer and the whole game mid-boot. It now **yields every 1000
  objects** — same objects, same token, same result, just without starving
  the VM
- **single-flight scan guard** — hook install, the boot animation and the
  diag panel could race each other into two concurrent full-heap scans
- the post-animation tail is **pcall'd**, and a **9 s failsafe** force-
  finishes the boot: boot card destroyed, HUD pill shown, main panel opened —
  the boot can no longer stick on screen, ever
- **loadstrings no longer use the HttpGet cache flag** — a stale cached build
  is a classic cause of "executed, nothing happened". If your pill still says
  `RS26.4`, your executor is serving an old cached copy: fully close Roblox
  and re-execute

**v26.4 — TIMING FIX (cross-map spam + early parries):**
- the trigger measured the **phantom ball** (position already pushed `offset`
  seconds into the future, up to ~200 studs ahead at speed) and the fire
  window added the **same offset again** — the lead was double-counted. A
  ball half a map away read as "10 studs" and `tti` read ~1 s small
- **TTI / lateral / proximity now measure the REAL ball position** — no more
  firing when you are on the other side of the map, no more parrying a ball
  that is still 300 studs out
- **fire window = the pure send lead** `1 × (pings + machineDelay)`
  (half the offset formula — its other half used to hide inside the phantom
  subtraction)
- the offset formula **still** drives the server-ball dot + prediction
  exactly as designed (`2 × (pings + machine)`)
- ~~🔒 protected builds~~ — **removed in v26.5.1** (they broke boot on Delta;
  both links serve the plain build again)

**v26.3 — SURVIVAL FIX:** auto spam only engages when the ball is actually
targeting YOU; fires capped 14/engagement @ 0.09 s; target-attribute flicker
can no longer re-arm the parry; panic lateral tolerance tightened.

**v26.2 — SMOOTH + MINIMAL update:**
- **BYAKU-BOT** — an ascii robot lives in the Dynamic Island: blinks, smiles, jumps up every now and then (zero-cost text animation)
- **Parry flash is now minimal white** (red removed)
- **PERF MODE toggle** — plastic-ifies parts, kills textures/decals/particles/trails/beams/highlights/shadows, drops render quality — snapshotted & fully restorable
- **Anti-lag HUD** — cached label writes, quantized TTI text, throttled stats, frozen cosmetic tweens in perf mode
- **Darker minimal RS theme** + staggered iOS row cascade on open

**v26.1 — LONG-RANGE HIGH-SPEED update:** time-to-impact interception,
second-order (curved) server-ball extrapolation, capped curve-veto, adaptive
cooldown + panic refire. No more dying to 500+ stud/s balls from 300+ studs.

## Run it (Delta mobile)

Main build (plain, v26.5.1):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR-USERNAME/scripts/main/bladeball/BladeBall_Byakugan_RS26.lua"))()
```

Vault link — currently serves the **same plain build** (kept so old saved
loadstrings keep working):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR-USERNAME/scripts/main/bladeball/BladeBall_Byakugan_RS26_vault.lua"))()
```

> Replace `YOUR-USERNAME` with your GitHub username. The repo must be public
> for `HttpGet` to reach the raw file (or make it private and fetch via the API).

## Engine (the working NAZK recipe)

1. `getgc` scan finds the **PRY time-token function** the game uses to sign
   every parry — homemade arguments can never pass server checks.
2. A metatable hook on every remote's `FireServer` / `InvokeServer` captures
   the first **8-argument packet the game itself sends**.
   👉 **Tap block once (manual parry) to arm the capture.**
3. Every auto-parry **replays that exact packet** with a fresh token, live
   curve CFrame and entity screen data.

## Parry math

```
parry_time_offset = 2 × (playerPing + clientPing + machineDelay)

serverBallPos = ballPos + ballVelocity × offset + ½ × accel × offset²
```

The offset extrapolates the **server-side ball position** (second-order:
per-frame acceleration tracking follows curved flight). The yellow dot shows
the extrapolated server ball in real time.

### v26.1 — time-to-impact interception (long range, high speed)

```
tti      = along-path distance / speed          (closest point on flight path,
                                                 measured from the REAL ball — v26.4)
lateral  = miss-distance of the path from you
fire when  tti ≤ fireWindow  AND  lateral ≤ hitRadius
fireWindow = clamp(offset/2 + 0.05 + speed/6000, 0.08, 0.42)   (v26.4: pure send lead)
proximity fallback uses REAL distance only (v26.4)
```

### v26.6 — PREDICT (optional)

```
lead       = PREDICT% × parry_time_offset          (OFF = 0)
measBall   = ballPos + vel × lead + ½ × accel × lead²
trigger    measures measBall instead of the real ball
fireWindow unchanged — predict adds lead on the MEASUREMENT side only,
           so the total lead = window + predict, never double-counted
```

- **Distance-independent** — a 700 stud/s ball triggers on TIME, never on a
  radius it can cross between two frames.
- **Curve-veto cap** — other players' parries can only block your parry for
  max 1.2 s regardless of range (was: `reachTime/1.1` = seconds of deafness
  at long range).
- **Adaptive cooldown** — `0.5 − speed/1600` (0.14–0.5 s): fast balls re-arm
  fast, so a wasted early fire can still be corrected.
- **PANIC refire** — contact imminent (`tti ≤ 50%` of window): fires anyway,
  curve veto ignored, up to 4 attempts per target cycle.
- **Proximity fallback** — the old radius trigger still handles slow/close
  balls (trusted under 140 stud/s, or inside 70 studs).

## Auto spam

```
distance(ball → its target) ≤ 15 studs  →  spam ENGAGES (rapid hook replays)
distance(ball → its target) > 22 studs  →  spam releases (hysteresis)
```

Toggle `AUTO SPAM <15` on the HUD (ON by default).

## HUD controls

| Control | What it does |
| --- | --- |
| AUTO PARRY | Master switch (ON at boot) |
| AUTO SPAM <15 | 15-stud auto spam engagement |
| PARRY SHOCKWAVE | Screen-edge glow + island ring on every parry |
| BYAKUGAN AURA | Red character highlight |
| SERVER DOT | Yellow server-ball prediction dot |
| PARRY METHOD | `Auto (Smart) · Hook Replay · Button · Firesignal · Remote` |
| CURVE MODE | `Camera · Random · Accelerated · Backwards · Slow · High · Normal · Speed · Down · Left · Right` |
| PREDICT | Future-ball lead: `OFF · 25% · 50% · 75% · 100%` of the parry offset (default OFF) |

Stats strip: **PING · BALL SPD · RADIUS · OFFSET** (live parry time offset).
Diagnostics: `RESCAN TOKEN` / `RE-ARM HOOK` buttons + token/capture caption.
The **Dynamic Island** pill shows live status — tap it to open/close the HUD.
Close (`×`) unloads the script completely.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Stuck at `booting…` / boot card % never finishes (v26.4 and older) | Fixed in v26.5 — the PRY scan used to freeze the whole game on big servers, and a dead animation thread could leave the boot card up forever. The scan now yields and a 9 s failsafe force-finishes the boot. Check the pill: it must say **`RS26.5`** — if it still says `RS26.4` you are running a stale cached build (fully close Roblox, re-execute) |
| Executed, nothing popped up | The green `[BYAK 1/6] → [BYAK ✓]` tracer pill top-center shows the live boot stage at all times. **No pill at all** → the fetch failed (check Delta console, re-execute, or GitHub rate-limited — wait a minute). **Pill turns red** → it prints the exact error — screenshot it and send it back. Plain build = real Lua errors in the Delta console too |
| `PRY NO GETGC` | Executor lacks `getgc` — hook replay unavailable, use Button method |
| Capture never arms | Tap block once manually so the game sends the real packet |
| Parries feel early/late | Watch the OFFSET stat — it is `2×(pings + machine delay)` by design; v26.4 fixed the double-counted lead, so fires now land ~`1×(pings+machine)` before contact |
| Dies at long range / high speed | Fixed in v26.1 — TTI trigger + panic refire. Watch the island: it shows live `TTI 0.xx` countdown when targeted |
| Fires when the ball is far away | Fixed in v26.4 — the trigger used the time-extrapolated ball and read it as "close"; it now measures the real ball only |
| Parries too early with PREDICT on | PREDICT adds extra lead on top of the v26.4 window by design — step it down (50% → 25%) or set OFF; OFF is the v26.5 timing exactly |
| Double parries, then dies on cooldown | Fixed in v26.7 — the second packet fired while the redirect was still replicating and wasted the parry cooldown before contact. TTI now fires once per approach and PANIC waits out `2 × ping + 0.06` first; the lockout ping is `max(Data Ping, GetNetworkPing)` so it can't collapse to 0 |
