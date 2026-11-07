# Blade Ball — BYAKUGAN RS27.3 (Audi RS × iOS 26 Fluid)

Mobile auto-parry for **Roblox Blade Ball**, built for **Delta iOS**.
The original **RS HUD** is back — Tango Red / Carbon Audi look — rebuilt with
iOS 26 liquid-glass motion: spring bounces, elastic pops, fluid steppers,
parry shockwaves, a Dynamic Island and an animated boot sequence.

**v27.3 — SPHERE TRIGGER + SMART SPAM (rebuild, user spec):**
- **the TTI/proximity trigger is replaced by a uniform sphere around
  you**: `R = (15 + √speed + speed × (2×ping + 0.06)) / 2`, clamped
  **15 → 50 studs** — starting 15, max 50, √ growth so a 900 stud/s
  ball can't make it giant. A sphere is uniform: it catches curves a
  box misses and reads the same from every angle
- **touch is measured on the ball's flight path every frame** — the
  path must pass inside the sphere within its lead time. Same result
  as a continuous touch test, but mobile frame drops can never tunnel
  past the sphere between two frames
- **the lead = the sphere's own crossing time** (`R / speed`), floored
  at the packet's send lead (`2×ping + 0.1`): a fast ball fires
  slightly BEFORE touching the sphere so the packet still lands
  before contact. NEURA's learned bias shifts this lead ±0.12 s
- **`isBallTargetting()` gate**: the sphere fires ONLY when the ball
  is locked on you — knockback/deflection pinballs grazing the sphere
  never double-click the remote
- **spam is no longer blind**: a vertical band (±3.1 studs around
  your root = your character height) gates it. A curve lifting the
  ball over your head (or dipping it under your feet) makes spam HOLD
  instantly — the sphere parry takes the shot — and spam resumes the
  moment the ball is back in band
- the parry METHOD is untouched: same NAZK hook replay, same packet,
  same curve CFrame

**v27.2 — PANIC REMOVED + SPAM RETUNE (user diagnosis):**
- **the last double was a fast curve — and it was PANIC, not the curve
  predictor**: on a hard curve the ball's velocity can flip in steps (the
  steerer re-aims mid-flight), the v27.1 dot < 0.3 latch can read those
  steps as steering and miss the true redirect instant, the lockout then
  expires while the ball still reads incoming, and PANIC — whose trigger
  (`tti ≤ 50%` of window, lateral ≤ 1.5× radius) is exactly a fast curve's
  signature — fired the **second packet**
- **PANIC is removed entirely.** It was the only branch that could ever
  fire twice on one approach, so a targeting double is now structurally
  impossible: TTI = exactly one packet per approach (v27.1 gate), spam =
  its own proximity system (multi-fire by design, never gated by this rule)
- a true miss now recovers via **AUTO SPAM**: engage widened **10 → 13
  studs** (release 14 → 16, hysteresis kept) — a wider net replaces the
  panic backstop
- spam "a bit too fast": throttle **0.02 → 0.03 s (~50 → ~33 packets/s)**,
  cap 30 kept — the saturation envelope stretches 0.6 → 0.9 s

**v27.1 — APPROACH RESOLVER (double-parry, round two):**
- **why v26.7 still doubled**: the once-per-approach gate released when the
  ball's velocity drifted more than 6 studs/s — but the ball **homes**, so a
  dodging target bends its velocity past that within ~0.1 s. The gate
  dissolved while the ball was still incoming, the lockout expired, and the
  TTI branch fired a **second packet on the same approach**. A deflected
  ball grazing you could also bait PANIC the instant the redirect changed
  the velocity
- the gate **no longer reads velocity at all**: TTI fires **exactly once per
  approach** — release only on a target change, a new ball, or a 1.2 s
  failsafe
- a per-frame watcher latches the approach-ending event: an **instant
  direction flip** (dot < 0.3 between frames — a curve bends < 5°/frame, a
  redirect is 90°+ at once), so curves can never false-trigger it
- **PANIC stays the true-miss last chance** (no flip seen, retries ≤ 4) but
  is **blocked once the redirect is observed** — a resolved approach can
  never spend the game's parry cooldown on a wasted packet
- a target change re-arms everything (fire record cleared + flip latch
  reset) — 1v1 rallies keep working

**v27.0 — NEURA NETWORK (new) + SPAM "even faster":**
- a real **8 → 6 → 1 neural network** (tanh MLP) trains **live on your own
  device** — inputs are the ball's position vs **your hitbox position** every
  frame (along-track time, lateral miss, real distance, vertical offset) plus
  ball speed, curve rate, ping and PREDICT level; the output is a **±0.12 s
  timing bias added to the fire window**
- training is supervised by what the **server did**: the moment the ball's
  velocity flips (> 72° in one frame — a curve bends < 5°/frame) the
  redirect has landed = your parry was accepted. Label =
  `fire − resolve + 2 × ping`, one SGD step per approach — **late parries
  widen the window, early parries narrow it**, so the timing converges on
  YOUR ping + device latency after ~10–20 approaches
- **zero at boot** (exact v26.9 behavior until the first sample) and spam
  shots are never trained on; hover balls (< 20 stud/s) and balls that never
  arrive are discarded
- **NEURA stepper**: `ON · OFF` (default ON; OFF = exact v26.9 timing).
  Re-executing resets the net — it re-learns in the first minutes of play
- spam retune: fire rate **0.04 → 0.02 s (~50 packets/s)**, engagement cap
  **20 → 30** (same 0.6 s envelope, double the density); ≤ 10 stud engage /
  14 release / hover-ball cooldowns unchanged

**v26.9 — SPAM OVERHAUL (tuned):**
- **proximity-only engage**: the ball within **10 studs of you**, regardless of
  who it is targeting — the target attribute flickers `nil` mid-flight and
  gating on it let close balls slip through unspammed (hysteresis release at
  14 studs)
- **fire rate 0.09 → 0.04 s** (~25 packets/s): spam exists to saturate the
  server's validation window — an 11/s trickle missed it on laggy frames
- per-engagement cap 14 → 20; release / post-cap cooldowns unchanged
  (0.6 s / 1 s) — an infinite spam on a hovering ball was redirecting it
  into you (v26.3 lesson kept)

**v26.8 — ROTATION CURVE (new):**
- the ball is steered by whoever it is locked ON: the server bends the
  flight with the steerer's replicated character rotation (camera flick =
  curve; first person is the mobile default, so their root yaw IS their
  view yaw — and it replicates to every client)
- the script now tracks the steering player's **yaw rate** (`d(yaw)/dt`)
  and predicts the lateral steering acceleration **before the ball's own
  motion shows it** — the measured acceleration always trails an active
  flick, which is exactly why curved balls used to fire panic-late
- physics: turning a velocity vector at rate `w` costs `speed × w` of
  sideways acceleration, so `a_rot = 0.4 × w × speed` toward the steerer's
  turn side, capped at 900, deadband `0.35 rad/s` (ordinary aim drift is
  not a curve)
- feeds the **PREDICT** measurement: `measBall` now uses
  `measured acc + rotation acc`
- **curve veto relaxed** under PREDICT + ROTATION: when the opponent's yaw
  rate confirms an active curve (`≥ 1 rad/s`) and the predicted path still
  passes inside your hit radius, the TTI branch may fire DURING the curve —
  on-time parries on curved balls instead of the late PANIC-only fire.
  Without PREDICT the veto behaves exactly as before
- new **ROTATION** stepper: `ON · OFF` (default ON — dormant until PREDICT
  is on; turn OFF to restore v26.7 curve handling exactly)

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

### v27.0 — NEURA timing bias (optional, ON by default)

```
sphereLead = max(R/speed, 2×ping + 0.1) + neuraBias        (v27.3)
neuraBias  = 0.12 × tanh( MLP( ball-vs-hitbox geometry ) )   ±0.12 s
trained on: label = fire − resolve + 2 × ping   (one SGD step / approach)
resolve    = velocity flip (> 72°/frame) = redirect landed,
             else closest approach within 15 studs
```

- output is **exactly 0** until the first resolved approach — boot behavior
  identical to v26.9
- the bias shifts the sphere's lead time, which
  is the point: it is a learned correction of YOUR end-to-end latency

### v27.3 — sphere trigger (replaces the TTI window)

```
R        = (15 + sqrt(speed) + speed × (2×ping + 0.06)) / 2   clamped 15..50
lead     = max(R / speed, 2×ping + 0.1)  capped 0.5 s  (+ NEURA bias)
fire when  tti ≤ lead  AND  lateral ≤ R      (path-touch, every frame)
gate     = isBallTargetting() — the ball must be locked on YOU
```

- `tti` / `lateral` are still the closest-point-on-path numbers measured
  from the REAL ball (v26.4) — the sphere replaces the old window + hit
  radius. The delay term converts ping to studs at the ball's own
  speed; the lead floor stops fast balls from being parried after
  contact

### v26.6 — PREDICT (optional)

```
lead       = PREDICT% × parry_time_offset          (OFF = 0)
measBall   = ballPos + vel × lead + ½ × accel × lead²          (v26.6)
           = ballPos + vel × lead + ½ × (accel + rotationAccel) × lead²   (v26.8)
trigger    measures measBall instead of the real ball
rotationAccel = 0.4 × yawRate(steerer) × speed, toward the steerer's turn side
fireWindow unchanged — predict adds lead on the MEASUREMENT side only,
           so the total lead = window + predict, never double-counted
```

- **Distance-independent** — a 700 stud/s ball triggers on TIME, never on a
  radius it can cross between two frames.
- **Curve-veto cap** — other players' parries can only block your parry for
  max 1.2 s regardless of range (was: `reachTime/1.1` = seconds of deafness
  at long range).
- **Adaptive cooldown** — `0.5 − speed/1600` (0.14–0.5 s): fast balls re-arm
  fast so the next approach after a redirect is covered.
- **No panic refire (v27.2)** — the old last-chance refire was the one
  branch that could double-fire an approach; it is removed entirely and a
  miss now recovers via the (wider) AUTO SPAM window.

## Auto spam

```
distance(ball → you) ≤ 13 studs  →  spam ENGAGES (hook replays, 0.03 s apart)
distance(ball → you) > 16 studs  →  spam releases (hysteresis)
ball height outside ±3.1 studs of root (over head / under feet)
                                 →  spam HOLDS — the sphere parry takes it
```

Pure proximity — targeting is ignored entirely (a flickering target
attribute used to leave close balls unspammed). Toggle `AUTO SPAM <13` on
the HUD (ON by default). Cap 30 fires per engagement at ~33/s (0.9 s
envelope), then a 1 s cooldown.

## HUD controls

| Control | What it does |
| --- | --- |
| AUTO PARRY | Master switch (ON at boot) |
| AUTO SPAM <13 | 13-stud auto spam engagement (proximity-only, ~33 fires/s) |
| PARRY SHOCKWAVE | Screen-edge glow + island ring on every parry |
| BYAKUGAN AURA | Red character highlight |
| SERVER DOT | Yellow server-ball prediction dot |
| PARRY METHOD | `Auto (Smart) · Hook Replay · Button · Firesignal · Remote` |
| CURVE MODE | `Camera · Random · Accelerated · Backwards · Slow · High · Normal · Speed · Down · Left · Right` |
| PREDICT | Future-ball lead: `OFF · 25% · 50% · 75% · 100%` of the parry offset (default OFF) |
| ROTATION | Rotation-curve prediction from the steering player's yaw rate (default ON; needs PREDICT to act) |
| NEURA | Self-learning timing net: watches ball vs your hitbox and shifts the sphere's lead ±0.12 s to your latency (default ON) |

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
| Dies at long range / high speed | Fixed in v26.1 + v27.3 — the sphere's send-lead floor keeps fast balls fireable at range (fired before touch, never after contact). Watch the island: it shows live `TTI 0.xx` countdown when targeted |
| Fires when the ball is far away | Fixed in v26.4 — the trigger used the time-extrapolated ball and read it as "close"; it now measures the real ball only |
| Parries too early with PREDICT on | PREDICT adds extra lead on top of the v26.4 window by design — step it down (50% → 25%) or set OFF; OFF is the v26.5 timing exactly |
| Curved balls still parry late (pre-v26.8 behavior) | Turn PREDICT on (25–50%) and keep ROTATION ON — the steerer's yaw rate leads the curve so TTI can fire during the bend. If a friend's curves predict the wrong side, flip ROTATION OFF and report it — the turn-side gain is tunable |
| Double parries, then dies on cooldown | v26.7 fired once per approach but its gate released on a 6 stud/s velocity drift — a homing ball bends past that in ~0.1 s, so the second packet still went out. **Fixed in v27.1**: the approach closes only on a target change / new ball / 1.2 s failsafe. **PANIC — the only branch that could still refire an approach — is removed entirely in v27.2**, so a targeting double is structurally impossible |
| Parry timing got worse after NEURA learned | Give it 10–20 approaches to converge (watch it settle); if a weird session poisoned it, re-execute the script — the net resets and re-learns. `NEURA OFF` = exact v26.9 timing |
| Spam drains too fast / too slow | Engagement is 30 fires @ ~33/s (0.9 s envelope, 0.03 s throttle — v27.2) with a 1 s post-cap cooldown — tuned so the saturation window covers `2 × ping + 0.06`; ask for a retune with your ping if it still misses |
