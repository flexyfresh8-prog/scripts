# Blade Ball — BYAKUGAN RS26 (Audi RS × iOS 26 Fluid)

Mobile auto-parry for **Roblox Blade Ball**, built for **Delta iOS**.
The original **RS HUD** is back — Tango Red / Carbon Audi look — rebuilt with
iOS 26 liquid-glass motion: spring bounces, elastic pops, fluid steppers,
parry shockwaves, a Dynamic Island and an animated boot sequence.

## Run it (Delta mobile)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR-USERNAME/scripts/main/bladeball/BladeBall_Byakugan_RS26.lua", true))()
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

serverBallPos = ballPos + ballVelocity × parry_time_offset
```

The offset extrapolates the **server-side ball position**; the parry fires
when the server ball (or the real ball) enters the NAZK parry-accuracy
radius (`ping + speed` derived). The yellow dot shows the extrapolated
server ball in real time.

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

Stats strip: **PING · BALL SPD · RADIUS · OFFSET** (live parry time offset).
Diagnostics: `RESCAN TOKEN` / `RE-ARM HOOK` buttons + token/capture caption.
The **Dynamic Island** pill shows live status — tap it to open/close the HUD.
Close (`×`) unloads the script completely.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `PRY NO GETGC` | Executor lacks `getgc` — hook replay unavailable, use Button method |
| Capture never arms | Tap block once manually so the game sends the real packet |
| Parries feel early/late | Watch the OFFSET stat — it is `2×(pings + machine delay)` by design; curve balls are skipped automatically |
