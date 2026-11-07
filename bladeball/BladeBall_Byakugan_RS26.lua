-- ============================================================
-- Blade Ball Mobile — BYAKUGAN RS27.4  (Audi RS × iOS 26 Fluid)
-- ============================================================
-- UI   : the original RS HUD is back — same Tango Red / Carbon
--        Audi look, rebuilt with iOS 26 liquid-glass motion:
--        spring bounces, elastic pops, fluid steppers, parry
--        shockwaves, Dynamic Island, animated boot.
-- ENGINE: the working NAZK recipe, untouched:
--        1. getgc scan -> PRY time-token function (signs every
--           parry; homemade args can NEVER pass server checks).
--        2. Metatable hook on every remote's FireServer /
--           InvokeServer -> the first 8-arg packet the GAME
--           itself sends is captured (tap block once to arm).
--        3. Auto-parry REPLAYS that exact packet with a fresh
--           token + live curve CFrame + entity screen data.
-- PARRY MATH:
--        parry_time_offset = 2 x (playerPing + clientPing
--                                    + machineDelay)
--        applied to extrapolate the SERVER-side ball position.
-- PARRY TRIGGER (v27.4 — SPHERE or TIMER, asked at boot):
--        1. Second-order extrapolation unchanged: server ball =
--           pos + vel*t + 0.5*acc*t^2 (curved flight tracked).
--        2. SPHERE TRIGGER: a uniform sphere around US. Radius
--           scales with the ball's velocity — starting 15 studs,
--           max 50:
--             R = (15 + sqrt(speed) + speed*(2*ping + 0.06)) / 2
--           (sqrt growth tames the giant-sphere problem; the
--           delay term converts ping to studs at the ball's own
--           speed). Touch = the ball's FLIGHT PATH passes inside
--           the sphere — re-measured EVERY frame, so curves are
--           caught and mobile frame drops cannot tunnel past it.
--        3. isBallTargetting(): the sphere fires ONLY when the
--           ball is locked on us — knockback/deflection pinballs
--           grazing the sphere can never double-fire.
--        4. Curve veto + adaptive cooldown + once-per-approach
--           gate kept exactly as they were.
--        5. v27.4 MODE CHOICE: on load the script ASKS — sphere
--           mode or timer mode — and uses whichever the user
--           picks (the menu PARRY MODE row re-chooses any time).
--           TIMER = the classic v26.4/v27.2 TTI send-lead
--           window + proximity fallback, restored verbatim.
--        6. v27.4 VISIBLE SPHERE: in sphere mode the live hitbox
--           renders as a red ForceField bubble around our
--           character, resized every frame with the radius.
-- AUTO SPAM:
--        proximity-only: the ball within 13 studs of YOU -> spam
--        ENGAGES (rapid hook-replay fires, 0.03 s apart) and
--        releases above 16 studs (hysteresis, no flicker) —
--        regardless of who the ball is targeting. v27.3: a
--        vertical band gates it — if the ball is curved OVER our
--        head or UNDER our feet (outside our character height)
--        spam HOLDS and the sphere parry takes the shot until
--        the ball is back in band.
-- Boot-safety: UI builds FIRST, no infinite waits, every error
--        shows a visible red panel instead of silent death.
-- v26.2 — SMOOTH + MINIMAL:
--        · BYAKU-BOT ascii robot lives in the Dynamic Island
--          (blinks, smiles, jumps up every now and then)
--        · parry flash is now minimal WHITE (red removed)
--        · PERF MODE: plastic-ifies parts, kills textures/
--          particles/shadows/beams/highlights, drops quality —
--          fully restorable on toggle-off
--        · anti-lag HUD: cached label writes, quantized TTI
--          text, throttled stats, frozen cosmetic tweens in perf
--        · darker minimal RS theme + staggered row cascade on open
-- v26.3 — SURVIVAL FIX (spam-kill bug):
--        · auto spam engages ONLY when the ball is actually coming
--          TO US (target == me) — spamming a ball that was passing
--          to someone else redirected it straight into us
--        · fires hard-capped at 14/engagement, throttled to 0.09 s
--        · target-attribute flicker can no longer re-arm the parry
--        · panic refire lateral tolerance tightened (1.5x radius)
-- v26.4 — TIMING FIX (cross-map spam + early parries):
--        the trigger was measuring the PHANTOM ball (pos already
--        pushed `offset` seconds into the future, up to ~200 studs
--        ahead at speed) and the fire window added the SAME offset
--        again on top — the lead was double-counted. Result: a ball
--        half a map away read as "10 studs" (proxHit) and tti read
--        ~1 s small (ttiHit) -> spam fires across the map + parries
--        way too early.
--        · TTI / lateral now measured from the REAL ball position
--        · proximity fallback uses REAL distance only
--        · fire window = the pure send lead: 1 x (pings + machine)
--          (= half the offset formula — its other half used to hide
--          inside the phantom-ball subtraction)
--        · the offset formula STILL drives the server-ball dot +
--          prediction exactly as designed (2 x pings + machine)
-- v26.5 — BOOT FAILSAFE ("never gets past booting" — fixed):
--        · getgc PRY scan now yields every 1000 objects — on long-
--          running servers the no-yield scan hogged the VM for 30+ s
--          and froze boot card / tracer / the whole game mid-boot
--        · single-flight scan guard: hook install, boot animation and
--          diag panel can no longer race each other into double scans
--        · post-animation tail is pcall'd; a 9 s failsafe force-
--          finishes the boot (card destroyed, HUD + panel opened) if
--          the animation thread ever dies mid-way
--        · executor fetches WITHOUT the HttpGet cache flag — a stale
--          cached build is a classic "executed, nothing happened"
-- v26.6 — PREDICT PARRY (new):
--        · PREDICT stepper: OFF / 25 / 50 / 75 / 100 % — the trigger
--          measures a PREDICTED future ball position instead of the
--          real one: lead = pct x parry offset, extrapolated with the
--          same second-order curve model as the yellow server dot
--        · fires earlier by design — for high ping or very fast balls
--          where the default window still feels a touch late
--        · the fire window is untouched (pure send lead): the predict
--          lead lives on the measurement side only, so the v26.4
--          double-count can never come back
--        · default OFF — current timing unchanged until you dial it in
-- v26.7 — ANTI-DOUBLE-PARRY (fix):
--        · the trigger could fire a SECOND packet on the same approach:
--          parryCooldown is only 0.14 s on fast balls, but the server's
--          "ball parried away" redirect takes 1-2 x ping (0.1-0.3 s) to
--          replicate — until it arrives the ball still reads as incoming
--          and targeting us, so TTI (no per-approach cap!) or PANIC
--          fired again. The wasted packet starts the game's parry
--          cooldown right before the real contact -> dead
--        · TTI branch now fires ONCE per approach: a refire needs the
--          ball state to actually CHANGE (redirect / curve / new target
--          / spam shot in between) — a stale incoming ball can no
--          longer re-trigger it
--        · post-fire lockout now covers replication: max(cooldown,
--          2 x ping + 0.06) — PANIC opens only after the redirect had
--          its chance to arrive, so a true miss still gets the last-
--          chance refire (retries <= 4 unchanged), a saved approach
--          stays silent
--        · lockout ping = max(Data Ping, GetNetworkPing): Data Ping can
--          read 0 for the first frames (or be missing on an executor)
--          and that silently shrank the lockout back to the 0.14 s
--          fast-ball cooldown — the double came back
-- v26.8 — ROTATION CURVE (new):
--        · the ball is steered by whoever it is locked ON: the server
--          bends the flight with the steerer's replicated character
--          rotation (camera flick = curve; first person is the mobile
--          default, so root yaw IS view yaw). The script now tracks
--          d(yaw)/dt of the steering player and predicts the lateral
--          steering acceleration BEFORE the ball's own motion shows
--          it — the measured acceleration always trails a flick
--        · physics: turning a velocity vector at rate w costs
--          speed x w of sideways accel, so a_rot = 0.4 x w x speed
--          toward the steerer's turn side, capped at 900, deadband
--          0.35 rad/s (ordinary aim drift is not a curve)
--        · feeds the PREDICT measurement: measured acc + rotation acc
--        · curve veto RELAXED under PREDICT + ROTATION: when the
--          opponent's yaw rate confirms an active curve (>= 1 rad/s)
--          and the predicted path still passes inside the hit radius,
--          the TTI branch may fire DURING the curve — on-time parries
--          on curved balls instead of the late PANIC-only fire.
--          Without PREDICT the veto behaves exactly as before
--        · new ROTATION stepper (ON/OFF, default ON — dormant until
--          PREDICT is on)
-- v26.9 — SPAM OVERHAUL (tuned):
--        · proximity-only engage: the ball within 10 studs of YOU,
--          regardless of who it is targeting — the target attribute
--          flickers nil mid-flight and gating on it let close balls
--          slip through unspammed (hysteresis release at 14 studs)
--        · fire rate 0.09 -> 0.04 s (~25 packets/s): spam exists to
--          saturate the server's validation window — an 11/s trickle
--          missed it on laggy frames
--        · per-engagement cap 14 -> 20; release / post-cap cooldowns
--          unchanged (0.6 s / 1 s) — an infinite spam on a hovering
--          ball was redirecting it into us (v26.3 lesson kept)
-- v27.0 — NEURA NETWORK (new) + SPAM "even faster":
--        · an 8 -> 6 -> 1 neural network trains LIVE on every
--          parry outcome. Inputs = the ball's position vs OUR
--          hitbox position every frame (along-track time, lateral
--          miss, real distance, vertical offset) + ball speed,
--          curve (yaw) rate, ping, PREDICT level. Output = a
--          +-0.12 s timing bias added to the TTI fire window
--        · supervised by what the SERVER did: the instant the
--          ball's velocity flips (> 72 deg in one frame — a curve
--          bends < 5 deg/frame) the redirect has landed; label =
--          fire - resolve + 2 x ping (the packet must arrive ~one
--          ping BEFORE server impact, the redirect is seen ~one
--          ping after). Late parries widen the window, early
--          parries narrow it — one SGD step per resolved approach
--        · zero-init output = exact no-op until samples exist;
--          converges to YOUR device latency after ~10-20
--          approaches. Spam shots are never trained on (saturation
--          timing is by design, not a timing signal)
--        · spam retune ("even faster"): fire rate 0.04 -> 0.02 s
--          (~50 packets/s), engagement cap 20 -> 30 (same 0.6 s
--          saturation envelope, double the density); <= 10 stud
--          engage / 14 release / hover-ball cooldowns unchanged
--        · new NEURA stepper (ON/OFF, default ON; OFF = exact
--          v26.9 behavior)
-- v27.1 — APPROACH RESOLVER (double-parry, round two):
--        · WHY v26.7 STILL DOUBLED: the once-per-approach gate
--          released when the ball's velocity drifted > 6 studs/s —
--          but the ball HOMES, so a dodging target bends it past
--          that within ~0.1 s. The gate dissolved, the lockout
--          expired, and the TTI branch fired a SECOND packet on the
--          same approach — plus a deflected ball grazing us could
--          bait PANIC the instant the redirect changed the velocity
--        · the gate no longer reads velocity at all: TTI fires
--          exactly ONCE per approach — release ONLY on a target
--          change, a new ball, or a 1.2 s failsafe
--        · a per-frame watcher latches the approach-ending event:
--          an instant direction flip (dot < 0.3 between frames — a
--          curve bends < 5 deg/frame, a redirect is 90+ at once)
--        · PANIC stays the true-miss last chance (no flip seen,
--          retries <= 4) but is BLOCKED once the redirect is
--          observed — a resolved approach can never spend the
--          game's parry cooldown on a wasted packet
--        · a target change re-arms everything (lastFireInfo cleared
--          + flip latch reset) — 1v1 rallies keep working
-- v27.2 — PANIC REMOVED + SPAM RETUNE (user diagnosis):
--        · the last double was a FAST CURVE. Not the curve
--          predictor — PANIC itself: on a hard curve the ball's
--          velocity can flip in STEPS (the steerer re-aims
--          mid-flight), the v27.1 dot < 0.3 latch can read those
--          steps as steering and miss the true redirect, the
--          lockout then expires while the ball still reads
--          incoming, and PANIC — whose trigger (tti <= HALF the
--          window, lateral <= 1.5x radius) is EXACTLY a fast
--          curve's signature — fired the SECOND packet
--        · PANIC is removed ENTIRELY. It was the only branch that
--          could ever fire twice on one approach, so a targeting
--          double is now structurally impossible: TTI = exactly
--          one packet per approach (v27.1 gate), spam = its own
--          proximity system (by design multi-fire, never gated)
--        · a true miss now recovers via AUTO SPAM: engage 10 ->
--          13 studs (release 14 -> 16, hysteresis kept) — a
--          wider net replaces the panic backstop
--        · spam "a bit too fast": throttle 0.02 -> 0.03 s
--          (~50 -> ~33 packets/s), cap 30 kept — the saturation
--          envelope stretches 0.6 -> 0.9 s
-- v27.3 — SPHERE TRIGGER + SMART SPAM (rebuild, user spec):
--        · the TTI/proximity trigger is REPLACED by a uniform
--          sphere around us: radius = (15 + sqrt(speed) +
--          speed*(2*ping + 0.06)) / 2, clamped 15..50 studs —
--          starting 15, max 50, sqrt growth so a 900 stud/s
--          ball cannot make it giant. A sphere is uniform: it
--          catches curves a box/radius misses and reads the
--          same from every angle
--        · touch is measured on the ball's FLIGHT PATH every
--          frame (path passes inside the sphere within its
--          lead time) — continuous-touch accuracy without
--          mobile frame-drop tunneling. The lead is the
--          sphere's own crossing time floored at the packet
--          send lead (2*ping + 0.1): a fast ball fires slightly
--          BEFORE touching the sphere so the packet still
--          lands first
--        · isBallTargetting(): the sphere only fires when the
--          ball targets US — knockback pinballs grazing the
--          sphere never double-click the remote
--        · SPAM no longer fires blindly: a vertical band
--          (+-3.1 studs around the root = our character
--          height) gates it. A skilled curve lifting the ball
--          over our head (or dipping it under our feet) makes
--          spam HOLD instantly — the sphere parry takes the
--          shot — and spam resumes the moment the ball is
--          back in band
--        · the parry METHOD is untouched: same NAZK hook
--          replay, same packet, same curve CFrame. NEURA /
--          PREDICT / ROTATION all keep working (NEURA's bias
--          now shifts the sphere's lead time)
-- v27.4 — MODE CHOICE + VISIBLE SPHERE (user request):
--        · on load the script ASKS: sphere mode or timer mode —
--          whichever the user picks is used (a 9 s no-touch keeps
--          SPHERE; the menu PARRY MODE row re-chooses any time,
--          and the boot card keeps the row label in sync)
--        · TIMER mode = the classic v26.4/v27.2 trigger restored
--          VERBATIM: ttiFireWindow send lead (half the offset
--          formula + speed ramp, clamp 0.08..0.42), accuracy
--          radius max(accuracy*0.55, 12), real-distance proximity
--          fallback — same fire, same NEURA bias on the window
--        · SPHERE mode now RENDERS the live hitbox: a red
--          ForceField bubble centered on the root, resized every
--          frame to the current sphere radius (hidden in timer
--          mode, on unload, and whenever auto parry is off)
--        · the parry METHOD stays untouched: same NAZK hook
--          replay, same 8-arg packet. Spam vertical band,
--          isBallTargetting gate, once-per-approach gate: all
--          identical in both modes
-- ============================================================

-- ============================================================
-- [0] BOOT TRACER — on-screen milestone pill. Every boot stage updates
--      it; any fatal error turns it red with the exact message. Kills
--      the "executed but nothing happened" blind spot for good.
-- ============================================================
local bootSay = nil
do
        pcall(function()
                local g = Instance.new("ScreenGui")
                g.Name = "ByakTrace"
                g.ResetOnSpawn = false
                g.IgnoreGuiInset = true
                g.DisplayOrder = 99999
                g.Parent = (typeof(gethui) == "function" and gethui())
                        or game:GetService("CoreGui")
                local t = Instance.new("TextLabel")
                t.AnchorPoint = Vector2.new(0.5, 0)
                t.Position = UDim2.new(0.5, 0, 0, 46)
                t.Size = UDim2.new(0, 440, 0, 30)
                t.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
                t.BackgroundTransparency = 0.12
                t.Font = Enum.Font.GothamBold
                t.TextSize = 12
                t.TextColor3 = Color3.fromRGB(120, 220, 140)
                t.Text = "[BYAK 1/6] services + tracer…"
                t.Parent = g
                Instance.new("UICorner", t).CornerRadius = UDim.new(0, 10)
                bootSay = function(s, bad)
                        pcall(function()
                                t.Text = s
                                t.TextColor3 = bad and Color3.fromRGB(255, 90, 90)
                                        or Color3.fromRGB(120, 220, 140)
                        end)
                end
                task.delay(45, function() pcall(function() g:Destroy() end) end)
        end)
end
if not bootSay then bootSay = function() end end

local function byakFatal(msg)
        bootSay("[BYAK ✖] " .. tostring(msg):sub(1, 90), true)
        pcall(function()
                local Players = game:GetService("Players")
                local lp = Players.LocalPlayer
                local g = Instance.new("ScreenGui")
                g.Name = "ByakuganBootError"
                g.ResetOnSpawn = false
                g.IgnoreGuiInset = true
                g.DisplayOrder = 99999
                local parented = pcall(function()
                        g.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
                end)
                if not parented and lp then
                        g.Parent = lp:WaitForChild("PlayerGui", 5)
                end
                local box = Instance.new("Frame")
                box.Size = UDim2.new(0, 320, 0, 170)
                box.Position = UDim2.new(0.5, -160, 0.5, -85)
                box.BackgroundColor3 = Color3.fromRGB(24, 8, 10)
                box.BorderSizePixel = 0
                box.Parent = g
                Instance.new("UICorner", box).CornerRadius = UDim.new(0, 18)
                local st = Instance.new("UIStroke", box)
                st.Color = Color3.fromRGB(255, 69, 58)
                st.Transparency = 0.4
                local t1 = Instance.new("TextLabel")
                t1.Size = UDim2.new(1, -24, 0, 22)
                t1.Position = UDim2.new(0, 12, 0, 10)
                t1.BackgroundTransparency = 1
                t1.Font = Enum.Font.GothamBold
                t1.TextSize = 15
                t1.TextColor3 = Color3.fromRGB(255, 90, 90)
                t1.TextXAlignment = Enum.TextXAlignment.Left
                t1.Text = "Byakugan failed to start"
                t1.Parent = box
                local t2 = Instance.new("TextLabel")
                t2.Size = UDim2.new(1, -24, 1, -44)
                t2.Position = UDim2.new(0, 12, 0, 36)
                t2.BackgroundTransparency = 1
                t2.Font = Enum.Font.Gotham
                t2.TextSize = 12
                t2.TextWrapped = true
                t2.TextColor3 = Color3.fromRGB(235, 235, 240)
                t2.TextXAlignment = Enum.TextXAlignment.Left
                t2.TextYAlignment = Enum.TextYAlignment.Top
                t2.Text = tostring(msg)
                t2.Parent = box
        end)
end

-- v26.6 PREDICT lead — declared in the MAIN CHUNK on purpose: the
-- xpcall body below sits AT the 200-active-local compiler limit
-- (PUC Lua and Luau both cap a function scope at 200), so this new
-- state must live out here and ride INTO the script as an upvalue.
local predictPct = 0 -- 0 = OFF; else lead fraction (0.25 / 0.5 / 0.75 / 1) of the parry offset
-- v26.7 anti-double-parry state — main chunk on purpose (the xpcall
-- body below is AT the 200-active-local compiler limit, so new state
-- rides in as an upvalue). Snapshot of the last auto fire: firing
-- again on the SAME ball with UNCHANGED target and velocity is a
-- wasted double — the redirect packet just hasn't replicated yet.
local lastFireInfo = nil
-- v26.8 ROTATION CURVE — main chunk on purpose (the xpcall body is AT
-- the 200-active-local compiler limit; new state rides in as upvalues).
-- While the ball is locked on a player, THAT player steers it: the
-- server bends the flight using the steerer's replicated character
-- rotation (camera flick = curve; first person is the mobile default,
-- so root yaw IS view yaw). Tracking d(yaw)/dt of the steering player
-- predicts the curve BEFORE the ball's own motion shows it — the
-- measured acceleration always trails an active flick.
local rotCurveOn = true
local yawTrack = {} -- [playerName] = { yaw, t, rate }
local rotLastRate = 0 -- |yaw rate| rad/s of the LAST rotCurveAccel call

-- Steering acceleration predicted from the steerer's yaw rate.
-- Turning a velocity vector at rate w costs speed x w of sideways
-- acceleration (centripetal identity); the game steers only partially,
-- so a gain < 1 plus a hard cap keep the prediction honest. Also sets
-- rotLastRate (single call site per frame reads it right after).
local function rotCurveAccel(targetName, speed)
        rotLastRate = 0
        if type(targetName) ~= "string" or targetName == "" then
                return Vector3.zero
        end
        local plr = game:GetService("Players"):FindFirstChild(targetName)
        local root = plr and plr.Character
                        and plr.Character:FindFirstChild("HumanoidRootPart")
        local tr = yawTrack[targetName]
        if not root then
                yawTrack[targetName] = nil
                return Vector3.zero
        end
        local look = root.CFrame.LookVector
        local hx, hz = look.X, look.Z
        if hx * hx + hz * hz < 0.0025 then
                -- staring near straight up/down — no yaw information
                return Vector3.zero
        end
        local yaw = math.atan2(-hx, -hz) -- 0 = facing -Z; LEFT turn = positive
        local now = os.clock()
        local rate = 0
        if tr then
                local dt = math.clamp(now - tr.t, 1 / 240, 0.25)
                local dYaw = yaw - tr.yaw
                if dYaw > math.pi then
                        dYaw = dYaw - 2 * math.pi
                elseif dYaw < -math.pi then
                        dYaw = dYaw + 2 * math.pi
                end
                rate = tr.rate + (dYaw / dt - tr.rate) * 0.35
        end
        yawTrack[targetName] = { yaw = yaw, t = now, rate = rate }
        rotLastRate = math.abs(rate)
        if rotLastRate < 0.35 then
                -- deadband: ordinary aim drift / homing wobble is not a curve
                return Vector3.zero
        end
        -- side points to the steerer's LEFT; a left turn (rate > 0) pushes
        -- the ball toward the steerer's left
        local side = Vector3.yAxis:Cross(Vector3.new(hx, 0, hz).Unit)
        local mag = math.clamp(0.4 * rotLastRate * speed, 0, 900)
        if rate < 0 then mag = -mag end
        return side * mag
end

-- ============================================================
-- v27.0 NEURA — a tiny online-trained neural net (8 -> 6 -> 1,
-- tanh) that learns YOUR parry timing from live outcomes.
-- Inputs = ball position vs OUR hitbox position, every frame:
-- along-track time, lateral miss, real distance, vertical offset,
-- ball speed, curve (yaw) rate, ping, PREDICT level. Output = a
-- +-0.12 s timing bias ADDED to the TTI fire window.
-- Training: every fired approach is observed until the server's
-- answer replicates — an instant velocity flip (> 72 deg/frame;
-- a curve bends < 5 deg/frame) is the redirect landing (parry
-- ON TIME), otherwise the closest approach is the impact. Label
-- = fire - resolve + 2 x ping (the packet must arrive ~one ping
-- BEFORE server impact and the redirect is seen ~one ping after),
-- then one SGD step (lr 0.2, loss on the normalized target so the
-- 0.12 s output scale never shrinks the gradient). Late parries widen the window,
-- early parries narrow it. Zero-init output = exact no-op until
-- samples exist; ~10-20 approaches to converge on a device.
-- ALL state lives in the main chunk: the xpcall body sits at the
-- 200-local compiler limit, so the body only calls neuraBias /
-- neuraObserve and tags fires with the pending sample.
-- ============================================================
local neuraOn = true
local neuraPending = nil -- this frame's NN inputs (attached at fire)
local neuraSession = nil -- the fired approach being observed
local neuraStats = { n = 0, err = 0 }
local nnW1, nnB1, nnW2, nnB2 = {}, {}, {}, {}
for j = 1, 6 do
        local row = {}
        for i = 1, 8 do
                row[i] = ((i + j) % 2 == 0) and 0.5 or -0.5
        end
        nnW1[j] = row
        nnB1[j] = 0
        nnW2[j] = 0 -- zero output head: EXACT no-op until first sample
end
nnB2[1] = 0

local function neuraFwd(x)
        local h = {}
        for j = 1, 6 do
                local w, z = nnW1[j], nnB1[j]
                for i = 1, 8 do z = z + w[i] * x[i] end
                h[j] = math.tanh(z)
        end
        local z2 = nnB2[1]
        for j = 1, 6 do z2 = z2 + nnW2[j] * h[j] end
        return math.tanh(z2), h
end

-- timing bias (seconds) for the CURRENT geometry; runs every
-- frame the fire window is computed and stores the sample that a
-- fire this frame would train on
local function neuraBias(root, ball, framePhys, vel, speed,
                tti, lateral, pingSec)
        if not neuraOn then
                neuraPending = nil -- no stale samples while OFF
                return 0
        end
        local bp, rp = ball and ball.Position, root and root.Position
        if not bp or not rp then return 0 end
        local x = {
                math.clamp(tti * 0.5, 0, 1.5),
                math.clamp(lateral / 12, 0, 3),
                math.clamp(speed / 200, 0, 5),
                math.clamp((bp - rp).Magnitude / 100, 0, 5),
                math.clamp((framePhys and framePhys.rotRate
                        or 0) / 3, 0, 1.5),
                math.clamp(pingSec * 5, 0, 1.5),
                math.clamp((rp.Y - bp.Y) / 50, -1.5, 1.5),
                predictPct,
        }
        local y = neuraFwd(x)
        neuraPending = { x = x, at = os.clock(), ping = pingSec,
                speed = speed }
        return 0.12 * y
end

local function neuraTrain(s, tResolve)
        local label = s.at - tResolve + 2 * s.ping
        if label > 0.12 then label = 0.12
        elseif label < -0.12 then label = -0.12 end
        local y, h = neuraFwd(s.x)
        -- loss on the NORMALIZED target: label/0.12 is in [-1, 1],
        -- the same range tanh outputs — full-size gradients
        local dOut = (y - label / 0.12) * (1 - y * y)
        local dh = {}
        for j = 1, 6 do
                dh[j] = (1 - h[j] * h[j]) * nnW2[j] * dOut
        end
        for j = 1, 6 do
                nnW2[j] = math.clamp(nnW2[j] - 0.2 * dOut * h[j], -3, 3)
        end
        nnB2[1] = math.clamp(nnB2[1] - 0.2 * dOut, -3, 3)
        for j = 1, 6 do
                local w, g = nnW1[j], 0.2 * dh[j]
                for i = 1, 8 do
                        w[i] = math.clamp(w[i] - g * s.x[i], -3, 3)
                end
                nnB1[j] = math.clamp(nnB1[j] - g, -3, 3)
        end
        neuraStats.n = neuraStats.n + 1
        neuraStats.err = neuraStats.err + math.abs(0.12 * y - label)
end

-- per-frame observer: arms from the last TTI fire (spam
-- shots carry no sample — saturation timing is by design, not a
-- timing signal), resolves the approach, trains once
local neuraMe = nil
local function neuraObserve(ball, root, framePhys)
        if not neuraOn or not root then
                neuraSession = nil
                return
        end
        local s = neuraSession
        if not s then
                local fi = lastFireInfo
                if fi and fi.nn and fi.ball == ball
                        and fi.nn.speed and fi.nn.speed > 20
                        and not fi.nnSeen then
                        fi.nnSeen = true
                        if not neuraMe then
                                neuraMe = game:GetService("Players")
                                        .LocalPlayer.Name
                        end
                        neuraSession = { ball = ball, x = fi.nn.x,
                                at = fi.nn.at, ping = fi.nn.ping,
                                minD = math.huge, tMin = 0,
                                dir = framePhys and framePhys.vel
                                        and framePhys.vel.Unit or nil }
                end
                return
        end
        if ball ~= s.ball then
                -- ball despawned / next round: resolve from what we saw
                if s.minD < 15 then neuraTrain(s, s.tMin) end
                neuraSession = nil
                return
        end
        local v = framePhys and framePhys.vel or nil
        if not v then
                local ok, av = pcall(function()
                        local z = ball:FindFirstChild("zoomies")
                        return z and z.VectorVelocity
                                or ball.AssemblyLinearVelocity
                end)
                if ok then v = av end
        end
        if not v or v.Magnitude < 1 then return end
        local dir = v.Unit
        if s.dir and s.dir:Dot(dir) < 0.3 then
                -- instant flip = the server redirect landed NOW
                neuraTrain(s, os.clock())
                neuraSession = nil
                return
        end
        s.dir = dir
        local d = (ball.Position - root.Position).Magnitude
        if d < s.minD then
                s.minD = d
                s.tMin = os.clock()
        end
        if os.clock() - s.at > 3 then
                if s.minD < 15 then neuraTrain(s, s.tMin) end
                neuraSession = nil
        end
end

-- ============================================================
-- v27.1 APPROACH RESOLVER — the double-parry killer, round two.
-- v26.7 gated the TTI refire on "velocity unchanged within 6
-- studs/s" — but the ball HOMES: its velocity tracks a dodging
-- target, so a 100 stud/s ball bends > 6 studs/s within ~0.1 s
-- and the gate dissolved long before the server's redirect had
-- its chance to arrive (2 x ping). After that the TTI branch was
-- free to fire a SECOND packet on the same approach — the double
-- the user still saw. The TTI branch now fires exactly ONCE per
-- approach: release only on target change / new ball / 1.2 s
-- failsafe (the sameApproach gate in the monitor loop).
-- v27.2: the per-frame flip watcher this block used to host is
-- GONE together with PANIC — its only reader WAS the PANIC gate
-- (block a refire once the redirect was seen), and NEURA's
-- observer latches that same flip on its own for training. One
-- less per-frame scan, six fewer main-chunk locals.
-- ============================================================

-- ============================================================
-- v27.3 SPHERE TRIGGER helpers — main-chunk upvalues (the xpcall
-- body sits at its 200-local limit; body code only calls these).
-- ============================================================
-- spamHold: spam suspends while the ball is curved over/under
-- our character (outside the vertical band) — the sphere parry
-- owns the shot until the ball is back in band.
local spamHold = false
-- isBallTargetting: the sphere fires ONLY when the ball is locked
-- on us. Deflected balls and knockback pinballs grazing the
-- sphere are ignored — no double clicks into the game's parry
-- cooldown (user spec).
local function isBallTargetting(ball)
        local t = ball and ball:GetAttribute("target")
        if not t then return false end
        local lp = game:GetService("Players").LocalPlayer
        return t == lp.Name
end

-- ============================================================
-- v27.4 PARRY MODE + VISIBLE SPHERE — main-chunk upvalues (the
-- xpcall body sits at its 200-local limit; body code only calls
-- these / assigns to them).
-- ============================================================
-- parryMode: which trigger geometry fires the parry — the
-- v27.3 velocity-scaled SPHERE, or the classic TIMER (the
-- v26.4/v27.2 TTI send-lead window + proximity fallback).
-- Asked at boot (chooser card); changeable in the menu any time.
local parryMode = "Sphere"
-- sphereVisual: the visible hitbox bubble (sphere mode only).
-- One local anchored Ball part, ForceField material, client-side
-- only — zero physics cost, resized every frame with the radius.
local sphereVisual = nil
-- parryModeSync: the menu assigns this so the boot chooser can
-- keep the PARRY MODE row's label (and step index) in sync.
local parryModeSync = nil
local function sphereVisShow(root, radius)
        pcall(function()
                if not (sphereVisual and sphereVisual.Parent) then
                        local p = Instance.new("Part")
                        p.Name = "ByakuganSphere"
                        p.Shape = Enum.PartType.Ball
                        p.Anchored = true
                        p.CanCollide = false
                        p.CanQuery = false
                        p.CanTouch = false
                        p.CastShadow = false
                        p.Massless = true
                        p.Material = Enum.Material.ForceField
                        p.Color = Color3.fromRGB(255, 69, 58)
                        p.Transparency = 0.5
                        p.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
                        p.CFrame = CFrame.new(root.Position)
                        p.Parent = workspace
                        sphereVisual = p
                        return
                end
                sphereVisual.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
                sphereVisual.CFrame = CFrame.new(root.Position)
                sphereVisual.Transparency = 0.5
        end)
end
local function sphereVisHide()
        if sphereVisual and sphereVisual.Parent then
                sphereVisual.Transparency = 1
        end
end
local function sphereVisDestroy()
        if sphereVisual then
                pcall(function() sphereVisual:Destroy() end)
                sphereVisual = nil
        end
end

xpcall(function()

-- ============================================================
-- [1] SERVICES + EXECUTOR PROBES
-- ============================================================
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local Stats            = game:GetService("Stats")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local get_connections = (typeof(getconnections) == "function" and getconnections)
        or (typeof(get_signal_cons) == "function" and get_signal_cons) or nil
local fire_signal = (typeof(firesignal) == "function" and firesignal)
        or (typeof(fire_signal) == "function" and fire_signal) or nil
local get_gc  = (typeof(getgc) == "function" and getgc) or nil
local rawMeta = (typeof(getrawmetatable) == "function" and getrawmetatable) or nil
local setRo   = (typeof(setreadonly) == "function" and setreadonly) or nil
local hookSupported = (get_gc and rawMeta and setRo) ~= nil
local unpack = unpack or table.unpack

local isMobileDevice = false
do
        local touch = UserInputService.TouchEnabled
        local mouse = UserInputService.MouseEnabled
        local keyboard = UserInputService.KeyboardEnabled
        isMobileDevice = (touch and not keyboard) or (touch and not mouse)
end
bootSay("[BYAK 2/6] state + engine…")

-- ============================================================
-- [2] STATE
-- ============================================================
local isRunning        = true         -- auto parry ON at boot
local dotEnabled       = true
local auraEnabled      = true
local autoSpamEnabled  = true         -- NEW: 15-stud auto spam
local fxEnabled        = true         -- parry shockwave FX
local perfMode         = false        -- HIGH PERFORMANCE mode
local parryMethod      = "Auto"       -- Auto | Hook | Button | Signal | Remote
local parryCurve       = "Camera"     -- NAZK curve list

local renderConn   = nil
local screenGui    = nil
local frameCount   = 0
local totalFires   = 0
local hookFires    = 0
local lastFireMethod = "none"
local lastResult     = "—"
local lastFireAt     = 0
local lastSpamAt     = 0
local spamFireCount  = 0
local spamActive     = false         -- auto-spam engaged state
local spamFires      = 0             -- fires in the CURRENT engagement
local spamCooldownUntil = 0          -- re-arm delay between engagements
local lastAutoFireAt = 0             -- shared throttle: ANY auto fire
local parriedUntil   = 0
local lastTtiBucket  = -1        -- anti-garbage TTI text bucket
local lastTargetOf   = {}
local deathActive    = false
local infActive      = false
local pingMs         = 0

-- every connection / task flag that must die on unload
local liveConns = {}
local uiAlive   = true

-- forward declarations (assigned later)
local fxBurst = nil    -- parry shockwave (UI assigns)
local unloadFn = nil   -- full unload (UI assigns)
local applyPerfUI = nil -- perf-mode UI gate (UI assigns)

-- ============================================================
-- [3] STATUS MACHINE (island + footer read from here)
-- ============================================================
local statusBase, transientText, transientUntil = "Idle", nil, 0

local function pushStatus(text, duration)
        transientText  = text
        transientUntil = os.clock() + (duration or 0.6)
end
local function setBaseStatus(text)
        statusBase = text
end
local function resolvedStatus()
        if transientText and os.clock() < transientUntil then
                return transientText
        end
        return statusBase
end

-- ============================================================
-- [4] LAZY WORLD RESOLVERS (never block the boot)
-- ============================================================
local ballsFolder, remotesFolder
local function getBalls()
        if ballsFolder and ballsFolder.Parent then return ballsFolder end
        ballsFolder = Workspace:FindFirstChild("Balls")
        return ballsFolder
end
local function getRemotes()
        if remotesFolder and remotesFolder.Parent then return remotesFolder end
        local ok, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
        if not ok or not rs then return nil end
        remotesFolder = rs:FindFirstChild("Remotes")
        return remotesFolder
end

-- ============================================================
-- [4b] PING CORE — player ping + client ping + machine delay
-- ============================================================
local playerPingSec   = 0.08     -- GetNetworkPing (seconds)
local dataPingMs      = 0        -- "Data Ping" stat (ms)
local machineDelaySec = 1 / 60   -- smoothed frame pipeline delay

local function getPingMs()
        local ok, v = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and v and v > 0 then dataPingMs = v end
        return dataPingMs
end

local function getPlayerPingSec()
        local ok, v = pcall(function() return LocalPlayer:GetNetworkPing() end)
        if ok and type(v) == "number" and v > 0 then playerPingSec = v end
        return playerPingSec
end

-- machine delay: smoothed RenderStepped delta (the whole render
-- + script pipeline stall — packets are late by at least this)
do
        local machineConn = RunService.RenderStepped:Connect(function(dt)
                if dt and dt > 0 then
                        local d = math.clamp(dt, 0.001, 0.25)
                        machineDelaySec = machineDelaySec + (d - machineDelaySec) * 0.08
                end
        end)
        table.insert(liveConns, machineConn)
end

-- THE FORMULA — parry_time_offset =
--   2 x (playerPing + clientPing + machineDelay), capped for sanity
local function getParryTimeOffset()
        local clientPing = getPingMs() / 1000
        local offset = 2 * (getPlayerPingSec() + clientPing + machineDelaySec)
        return math.clamp(offset, 0, 0.5)
end

-- ============================================================
-- [5] BALL HELPERS
-- ============================================================
local function setupAura()
        local char = LocalPlayer.Character
        if not char then return end
        local hl = char:FindFirstChild("ByakuganAura")
        if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "ByakuganAura"
                hl.FillColor = Color3.fromRGB(200, 0, 0)
                hl.OutlineColor = Color3.fromRGB(255, 50, 50)
                hl.FillTransparency = 0.85
                hl.OutlineTransparency = 0
                hl.Enabled = auraEnabled
                hl.Parent = char
        end
end

local serverBallDot = Instance.new("Part")
serverBallDot.Shape = Enum.PartType.Ball
serverBallDot.Anchored = true
serverBallDot.CanCollide = false
serverBallDot.CanQuery = false
serverBallDot.CanTouch = false
serverBallDot.Material = Enum.Material.Neon
serverBallDot.Color = Color3.fromRGB(255, 255, 0)
serverBallDot.Size = Vector3.new(1.5, 1.5, 1.5)
serverBallDot.Transparency = dotEnabled and 0 or 1
serverBallDot.Parent = Workspace

setupAura()
do
        local auraConn = LocalPlayer.CharacterAdded:Connect(function()
                task.wait(1)
                if uiAlive then setupAura() end
        end)
        table.insert(liveConns, auraConn)
end

local function ballVelocity(ball)
        local ok, v = pcall(function()
                local z = ball:FindFirstChild("zoomies")
                if z then return z.VectorVelocity end
                return ball.AssemblyLinearVelocity
        end)
        if ok and v then return v end
        return Vector3.new()
end

local function getActiveBall()
        local folder = getBalls()
        if not folder then return nil end
        local best, bestSpeed = nil, 0
        for _, ball in pairs(folder:GetChildren()) do
                if ball:IsA("BasePart") then
                        if ball:GetAttribute("realBall") == true then
                                return ball
                        end
                        local sp = ballVelocity(ball).Magnitude
                        if sp > bestSpeed then bestSpeed, best = sp, ball end
                end
        end
        if bestSpeed > 25 then return best end
        return nil
end

-- the player the ball is currently homing at (or nil)
local function ballTargetPlayer(ball)
        local ok, name = pcall(function() return ball:GetAttribute("target") end)
        if not ok or type(name) ~= "string" then return nil end
        local plr = Players:FindFirstChild(name)
        if not plr then return nil end
        local char = plr.Character
        if not char then return nil end
        return plr, char:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- [6] HOOK ENGINE — token + capture (NAZK exact)
-- ============================================================
local hookState = {
        tokenFn = nil, tokenOk = false,
        captured = nil, capturedArgs = nil,
        captureCount = 0, path = "none", announced = false,
}
local hookMetas, hookStored = {}, {}

local function sourceNameOf(f)
        local ok, s = pcall(function()
                if type(debug) == "table" and type(debug.info) == "function" then
                        return debug.info(f, "s")
                end
                return nil
        end)
        if ok and type(s) == "string" then return s end
        return nil
end

local function upvalsOf(f)
        local ok, ups = pcall(function()
                if type(debug) == "table" and type(debug.getupvalues) == "function" then
                        return debug.getupvalues(f)
                end
                return nil
        end)
        if ok and type(ups) == "table" then return ups end
        return nil
end

-- v26.5: single-flight guard — installHook, the boot animation and
-- the diag panel all call this; two concurrent getgc scans would
-- double-freeze the VM on busy servers.
local scanBusy = false
local function findTokenFunction()
        if hookState.tokenOk then return true end
        if not get_gc then return false end
        if scanBusy then return false end
        scanBusy = true
        local found
        local scanned = 0
        pcall(function()
                for _, obj in get_gc(true) do
                        scanned = scanned + 1
                        if scanned % 1000 == 0 then
                                -- v26.5: yield to the scheduler — on old,
                                -- bloated servers the no-yield scan froze the
                                -- whole boot for 30+ s. Same objects, same
                                -- token found, just without starving the VM.
                                task.wait()
                        end
                        if type(obj) == "function" then
                                local src = sourceNameOf(obj)
                                if src and src:find("PRY", 1, true) then
                                        local ups = upvalsOf(obj)
                                        if ups then
                                                for _, v in pairs(ups) do
                                                        if type(v) == "function" then found = v break end
                                                end
                                        end
                                end
                        end
                        if found then break end
                end
        end)
        scanBusy = false
        if found then
                hookState.tokenFn = found
                hookState.tokenOk = true
        end
        return hookState.tokenOk
end

-- Blade Ball's tokenizer: time string XOR'd with the PRY key
local function parryToken(remoteUid)
        if not hookState.tokenOk then return nil end
        local ok, token = pcall(function()
                local time = tostring(math.floor(Workspace:GetServerTimeNow() * 100))
                local key = hookState.tokenFn(remoteUid, "TIME")
                if type(key) ~= "string" or #key == 0 then return nil end
                local chars = table.create(#time)
                for i = 1, #time do
                        chars[i] = string.char(bit32.bxor(
                                (string.byte(time, i) + i) % 256,
                                string.byte(key, (i - 1) % #key + 1)
                        ))
                end
                return table.concat(chars)
        end)
        if ok then return token end
        return nil
end

local function hookRemote(remote)
        if not hookSupported or not remote then return end
        if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then return end
        local meta = rawMeta(remote)
        if not meta or hookMetas[meta] then return end
        hookMetas[meta] = true
        pcall(function()
                setRo(meta, false)
                local oldIndex = meta.__index
                meta.__index = function(self, key)
                        if (key == "FireServer" and self:IsA("RemoteEvent"))
                                or (key == "InvokeServer" and self:IsA("RemoteFunction")) then
                                return function(_, ...)
                                        local args = { ... }
                                        if #args >= 8 and not hookStored[self] then
                                                hookStored[self] = args
                                                hookState.captureCount = hookState.captureCount + 1
                                                local isParry = self.Name:lower():find("parry", 1, true) ~= nil
                                                local stale = hookState.captured ~= nil
                                                        and hookState.captured.Parent == nil
                                                if isParry or not hookState.captured or stale then
                                                        hookState.captured = self
                                                        hookState.capturedArgs = args
                                                        pcall(function() hookState.path = self:GetFullName() end)
                                                end
                                                if not hookState.announced then
                                                        hookState.announced = true
                                                        pushStatus("Hook armed", 1.6)
                                                end
                                        end
                                        return oldIndex(self, key)(_, unpack(args))
                                end
                        end
                        return oldIndex(self, key)
                end
                setRo(meta, true)
        end)
end

local hookInstalled = false
local function installHook()
        if hookInstalled then return hookSupported end
        hookInstalled = true
        findTokenFunction()
        if hookSupported then
                local ok, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
                if ok and rs then
                        pcall(function()
                                for _, inst in pairs(rs:GetDescendants()) do
                                        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                                                hookRemote(inst)
                                        end
                                end
                        end)
                end
        end
        return hookSupported
end
task.spawn(installHook)

-- Also hook remotes that appear later (Knit loads async)
task.spawn(function()
        local ok, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
        if not ok or not rs then return end
        pcall(function()
                rs.DescendantAdded:Connect(function(inst)
                        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                                task.defer(hookRemote, inst)
                        end
                end)
        end)
end)

-- ============================================================
-- [7] NAZK CURVE SYSTEM (all 11 modes) + curve detection
-- ============================================================
local curveProps = { lerpRadians = 0, lastWarping = 0, curving = 0, ball = nil }

local function getCurveTarget()
        local cam = Workspace.CurrentCamera
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local rootPos = root and root.Position or (cam and cam.CFrame.Position) or Vector3.new()
        local targetPart, bestDist = nil, math.huge
        local mouseLoc = nil
        if not isMobileDevice then
                pcall(function() mouseLoc = UserInputService:GetMouseLocation() end)
        end
        local alive = Workspace:FindFirstChild("Alive")
        if cam and alive then
                for _, v in pairs(alive:GetChildren()) do
                        if v ~= char and v.PrimaryPart then
                                local ok, sp = pcall(function() return cam:WorldToScreenPoint(v.PrimaryPart.Position) end)
                                if ok and sp then
                                        local dist
                                        if mouseLoc then
                                                dist = (Vector2.new(sp.X, sp.Y) - mouseLoc).Magnitude
                                        else
                                                local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                                                dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                                        end
                                        if dist < bestDist then bestDist, targetPart = dist, v.PrimaryPart end
                                end
                        end
                end
        end
        local targetPos = targetPart and targetPart.Position
                or (rootPos + ((cam and cam.CFrame.LookVector) or Vector3.new()) * 100)
        return cam, rootPos, targetPos
end

local function getCurveCFrame()
        local cam, rootPos, targetPos = getCurveTarget()
        if not cam then return CFrame.new(rootPos) end
        local mode = parryCurve
        local cf
        if mode == "Camera" then
                cf = cam.CFrame
        elseif mode == "Random" then
                local direction = (targetPos - rootPos).Unit
                local offset, dot, attempts = Vector3.new(), 1, 0
                repeat
                        offset = Vector3.new(math.random(-4000, 4000), math.random(-4000, 4000), math.random(-4000, 4000))
                        dot = direction:Dot((targetPos + offset - rootPos).Unit)
                        attempts = attempts + 1
                until dot < 0.95 or attempts > 10
                cf = CFrame.new(rootPos, targetPos + offset)
        elseif mode == "Accelerated" then
                cf = CFrame.new(rootPos, targetPos + Vector3.new(0, 5, 0))
        elseif mode == "Backwards" then
                local direction = (rootPos - targetPos).Unit
                cf = CFrame.new(cam.CFrame.Position, rootPos + direction * 10000 + Vector3.new(0, 1000, 0))
        elseif mode == "Slow" then
                cf = CFrame.new(rootPos, targetPos + Vector3.new(0, -9e18, 0))
        elseif mode == "High" then
                cf = CFrame.new(rootPos, targetPos + Vector3.new(0, 9e18, 0))
        elseif mode == "Normal" then
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                cf = CFrame.new(rootPos, rootPos + (root and root.CFrame.LookVector or cam.CFrame.LookVector))
        elseif mode == "Speed" then
                cf = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + cam.CFrame.UpVector * 5)
        elseif mode == "Down" then
                cf = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + cam.CFrame.UpVector * -9e9)
        elseif mode == "Left" then
                cf = CFrame.new(cam.CFrame.Position, cam.CFrame.Position - cam.CFrame.RightVector * 9e9)
        elseif mode == "Right" then
                cf = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + cam.CFrame.RightVector * 9e9)
        else
                cf = cam.CFrame
        end
        return cf
end

local function isCurved(ball, pingSec)
        local zoomies = ball:FindFirstChild("zoomies")
        if not zoomies then return false end
        local velocity = zoomies.VectorVelocity
        local speed = velocity.Magnitude
        if speed < 1 then return false end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        if curveProps.ball ~= ball then
                curveProps.ball = ball
                curveProps.lerpRadians = 0
        end
        local direction = (root.Position - ball.Position).Unit
        local dot = direction:Dot(velocity.Unit)
        local distance = (root.Position - ball.Position).Magnitude
        local reachTime = distance / speed - pingSec
        local dotThreshold = math.clamp(0.55 - pingSec * 0.75, -1, 0.45)
        local speedThreshold = math.min(speed / 100, 45)
        local distThreshold = 15 - math.min(distance / 1000, 15) + speedThreshold
        local radians = math.asin(math.clamp(dot, -1, 1))
        curveProps.lerpRadians = curveProps.lerpRadians + (radians - curveProps.lerpRadians) * 0.85
        if curveProps.lerpRadians < 0.016 then curveProps.lastWarping = os.clock() end
        if distance < distThreshold * 0.85 then return false end
        -- v26.1: cap the veto windows — at long range reachTime is
        -- huge and the old math kept the parry deaf for seconds.
        if os.clock() - curveProps.lastWarping < math.min(reachTime / 1.4, 1.2) then return true end
        if os.clock() - curveProps.curving < math.min(reachTime / 1.1, 1.2) then return true end
        return dot < dotThreshold
end

-- NAZK parry-accuracy radius: ping + speed derived
local function parryAccuracy(speed, pingSec)
        local pingThreshold = math.clamp(pingSec * 10, 5, 20)
        local capped = math.min(math.max(speed - 9.5, 0), 900)
        local divisor = 2.4 + capped * 0.0018
        return pingThreshold + math.max(speed / divisor, 9.5)
end

-- ============================================================
-- [7b] LONG-RANGE HS — TTI interception core (v26.1)
-- ============================================================
-- Per-ball velocity tracking -> ACCELERATION estimate, so the
-- server-ball extrapolation follows CURVED flight instead of a
-- straight line that lies more the further the ball is.
local ballVelTrack = {}
local function serverBallPos(ball, zoomies, offset)
        local vel = zoomies.VectorVelocity
        local now = os.clock()
        local acc = Vector3.zero
        local prev = ballVelTrack[ball]
        if prev then
                local dt = now - prev.t
                if dt > 0.001 and dt < 0.25 then
                        acc = (vel - prev.v) / dt
                        local am = acc.Magnitude
                        if am > 600 then
                                acc = acc * (600 / am)
                        end
                end
        end
        ballVelTrack[ball] = { v = vel, t = now }
        -- occasional sweep of destroyed balls (tiny state, stays tiny)
        if math.random(1, 120) == 1 then
                for b in pairs(ballVelTrack) do
                        if not b.Parent then ballVelTrack[b] = nil end
                end
        end
        return ball.Position + vel * offset + acc * (offset * offset * 0.5), acc
end

-- (v27.3 note: the sphere trigger carries its own lead — the
-- sphere's crossing time floored at the packet's send lead.)
-- v27.4: the window is BACK as TIMER mode's trigger — restored
-- verbatim from v26.4/v27.2 so the classic feel is identical.

-- Fire window (TIMER mode): how many seconds BEFORE impact we
-- release the parry so the request lands inside the server's
-- validation window. The pure send lead = 1 x (pings + machine)
-- — HALF the offset formula (the other half used to hide inside
-- the phantom subtraction, double-counting the lead).
local function ttiFireWindow(speed)
        local w = getParryTimeOffset() * 0.5 + 0.05 + speed / 6000
        return math.clamp(w, 0.08, 0.42)
end

-- Adaptive cooldown: fast balls re-arm FAST so the next
-- approach after a redirect is covered; slow balls stay quiet.
local function parryCooldown(speed)
        return math.clamp(0.5 - speed / 1600, 0.14, 0.5)
end

-- ============================================================
-- [8] FIRING CHAIN — hook replay -> button -> remote
-- ============================================================
local function fireParryRemote(curveCF)
        if not hookState.captured or not hookState.capturedArgs then return false end
        local ok, did = pcall(function()
                local cam = Workspace.CurrentCamera
                local aim
                if isMobileDevice then
                        local vp = cam.ViewportSize
                        aim = { math.floor(vp.X / 2), math.floor(vp.Y / 2) }
                else
                        local mok, mouse = pcall(function() return UserInputService:GetMouseLocation() end)
                        if mok and mouse then
                                aim = { math.floor(mouse.X), math.floor(mouse.Y) }
                        else
                                local vp = cam.ViewportSize
                                aim = { math.floor(vp.X / 2), math.floor(vp.Y / 2) }
                        end
                end
                local eventData = {}
                local alive = Workspace:FindFirstChild("Alive")
                if alive then
                        for _, e in pairs(alive:GetChildren()) do
                                if e.PrimaryPart then
                                        local sok, sp = pcall(function() return cam:WorldToScreenPoint(e.PrimaryPart.Position) end)
                                        if sok and sp then eventData[e.Name] = sp end
                                end
                        end
                end
                local args = hookState.capturedArgs
                local packet = {
                        args[1], args[2], parryToken(args[2]), 0.5,
                        curveCF or cam.CFrame, eventData, aim, false,
                }
                if hookState.captured:IsA("RemoteEvent") then
                        hookState.captured:FireServer(unpack(packet))
                else
                        hookState.captured:InvokeServer(unpack(packet))
                end
                return true
        end)
        if ok and did then
                hookFires = hookFires + 1
                totalFires = totalFires + 1
                lastFireMethod = "hook replay"
                lastFireAt = os.clock()
                return true
        end
        return false
end

-- --- Block button (used to arm capture + as a fallback method)
local blockButton, blockScanAt = nil, 0
local function findBlockButton()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return nil end
        local hotbar = pg:FindFirstChild("Hotbar")
        if hotbar then
                local direct = hotbar:FindFirstChild("Block")
                if direct and direct:IsA("GuiButton") then return direct end
        end
        local best, bestY = nil, math.huge
        for _, v in pairs(pg:GetDescendants()) do
                if v:IsA("GuiButton") and v.Visible then
                        local n = v.Name:lower()
                        if n:find("block", 1, true) or n:find("parry", 1, true) or n:find("fight", 1, true) then
                                local ok, pos = pcall(function() return v.AbsolutePosition end)
                                if ok and pos.Y < bestY then bestY, best = pos.Y, v end
                        end
                end
        end
        return best
end
local function getBlockButton()
        local now = os.clock()
        if blockButton and blockButton.Parent and now - blockScanAt < 3 then
                return blockButton
        end
        blockScanAt = now
        blockButton = findBlockButton()
        return blockButton
end

local function fireButtonChain()
        local btn = getBlockButton()
        if not btn then return false end
        local fired = false
        if get_connections then
                pcall(function()
                        for _, sig in ipairs({ btn.Activated, btn.MouseButton1Click, btn.MouseButton1Down, btn.TouchTap }) do
                                for _, c in pairs(get_connections(sig)) do
                                        pcall(function() c.Fire(c) end)
                                        fired = true
                                end
                        end
                end)
        end
        if fire_signal then
                pcall(function()
                        fire_signal(btn.Activated)
                        fired = true
                end)
        end
        if fired then
                lastFireMethod = "button"
                lastFireAt = os.clock()
        end
        return fired
end

-- --- Last-resort: ParryAttempt FireServer variants
local parryRemoteCache
local function getParryRemote()
        if parryRemoteCache and parryRemoteCache.Parent then return parryRemoteCache end
        local remotes = getRemotes()
        if not remotes then return nil end
        parryRemoteCache = remotes:FindFirstChild("ParryAttempt")
        return parryRemoteCache
end
local function remoteFireVariants()
        local remote = getParryRemote()
        if not remote then return false end
        local sent = false
        pcall(function() remote:FireServer() sent = true end)
        if not sent then
                pcall(function() remote:FireServer(0.5) sent = true end)
        end
        if not sent then
                pcall(function() remote:FireServer(true) sent = true end)
        end
        if sent then
                lastFireMethod = "remote"
                lastFireAt = os.clock()
        end
        return sent
end

local function fireSelected()
        totalFires = totalFires + 1
        lastFireAt = os.clock()
        local m = parryMethod
        if m == "Hook" or m == "Auto" then
                if fireParryRemote(getCurveCFrame()) then
                        lastResult = "hook"
                        pushStatus("Hook fired", 0.5)
                        return
                end
                if m == "Hook" then
                        if not hookState.captured then
                                lastResult = "arming…"
                                fireButtonChain() -- makes the GAME fire the real packet
                        else
                                lastResult = "hook err"
                        end
                        return
                end
        end
        if (m == "Auto" or m == "Button") and fireButtonChain() then
                lastResult = "button"
                return
        end
        if m == "Auto" or m == "Signal" then
                local btn = getBlockButton()
                if btn and fire_signal then
                        local ok = pcall(function() fire_signal(btn.Activated) end)
                        if ok then
                                lastFireMethod = "signal"
                                lastResult = "signal"
                                return
                        end
                end
        end
        if m == "Auto" or m == "Remote" then
                if remoteFireVariants() then
                        lastResult = "remote"
                        return
                end
        end
        lastResult = "no path"
end

-- ============================================================
-- [9] REACTIVE LAYER — ParrySuccessAll curve responder (NAZK)
-- ============================================================
task.spawn(function()
        local remotes
        for _ = 1, 30 do
                remotes = getRemotes()
                if remotes then break end
                task.wait(1)
        end
        if not remotes then return end

        local function onParrySuccessAll(_, b)
                pcall(function()
                        -- bookmark curves that are NOT coming to us (NAZK)
                        local char = LocalPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local ball = getActiveBall()
                        if root and ball and b ~= root and b ~= char then
                                local zoomies = ball:FindFirstChild("zoomies")
                                if zoomies and zoomies.VectorVelocity.Magnitude > 1 then
                                        local distance = (root.Position - ball.Position).Magnitude
                                        if distance > parryAccuracy(zoomies.VectorVelocity.Magnitude, getPingMs() / 1000) then
                                                curveProps.curving = os.clock()
                                        end
                                end
                        end
                        -- reactive parry: a parry just resolved next to us and the
                        -- ball is curving onto us — fire NOW (proactive math lies)
                        if not isRunning then return end
                        local ch = LocalPlayer.Character
                        local rt = ch and ch:FindFirstChild("HumanoidRootPart")
                        local bl = getActiveBall()
                        local alive = Workspace:FindFirstChild("Alive")
                        if not (bl and rt and alive) then return end
                        local closest, closestDist = nil, math.huge
                        for _, e in pairs(alive:GetChildren()) do
                                if e ~= ch and e.PrimaryPart then
                                        local ok, d = pcall(function() return LocalPlayer:DistanceFromCharacter(e.PrimaryPart.Position) end)
                                        if ok and d < closestDist then closestDist, closest = d, e end
                                end
                        end
                        if not closest then return end
                        local zoomies = bl:FindFirstChild("zoomies")
                        if not zoomies then return end
                        local v = zoomies.VectorVelocity
                        if v.Magnitude < 1 then return end
                        local targetDist = (rt.Position - closest.PrimaryPart.Position).Magnitude
                        local dist = (rt.Position - bl.Position).Magnitude
                        local dot = ((rt.Position - bl.Position).Unit):Dot(v.Unit)
                        if targetDist < 15 and dist < 15 and dot > -0.25 and isCurved(bl, getPingMs() / 1000) then
                                pushStatus("Parrying", 0.8)
                                fireSelected()
                        end
                end)
        end
        pcall(function() remotes.ParrySuccessAll.OnClientEvent:Connect(onParrySuccessAll) end)
        pcall(function()
                remotes.DeathBall.OnClientEvent:Connect(function(_, d) deathActive = d and true or false end)
        end)
        pcall(function()
                remotes.InfinityBall.OnClientEvent:Connect(function(_, b) infActive = b and true or false end)
        end)
end)

-- ============================================================
-- [10] UI KIT — RS theme × iOS 26 liquid-glass motion
-- ============================================================
local THEME = {
        Red       = Color3.fromRGB(187, 10, 48),  -- Audi Tango Red
        RedGlow   = Color3.fromRGB(255, 45, 70),
        Carbon    = Color3.fromRGB(9, 9, 12),     -- v26.2: deeper dark
        Panel     = Color3.fromRGB(16, 16, 20),
        PanelDark = Color3.fromRGB(13, 13, 16),
        Hover     = Color3.fromRGB(24, 24, 29),
        Stroke    = Color3.fromRGB(38, 38, 45),
        Text      = Color3.fromRGB(238, 238, 240),
        TextDim   = Color3.fromRGB(120, 120, 128),
        Glass     = Color3.fromRGB(255, 255, 255),
        Amber     = Color3.fromRGB(255, 159, 10),
        Good      = Color3.fromRGB(52, 199, 89),
        Bad       = Color3.fromRGB(255, 69, 58),
}

local function create(className, props, children)
        local inst = Instance.new(className)
        for k, v in pairs(props or {}) do inst[k] = v end
        for _, child in ipairs(children or {}) do child.Parent = inst end
        return inst
end
local function corner(inst, r)
        return create("UICorner", { CornerRadius = UDim.new(0, r), Parent = inst })
end
local function fullCorner(inst)
        return create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = inst })
end
local function stroke(inst, color, thickness, transparency)
        return create("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency, Parent = inst })
end
local function tw(inst, time, props, style, dir, repeats, reverses)
        return TweenService:Create(inst, TweenInfo.new(
                time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out,
                repeats or 0, reverses or false), props)
end
-- elastic pop on any UIScale (the iOS 26 "squish")
local popTokens = {}
local function elasticPop(scaleObj, strength)
        if not scaleObj or not scaleObj.Parent then return end
        local id = popTokens[scaleObj]
        popTokens[scaleObj] = (id or 0) + 1
        scaleObj.Scale = strength
        tw(scaleObj, 0.7, { Scale = 1 }, Enum.EasingStyle.Elastic):Play()
end
local function sheen(parent, height, radius)
        local s = create("Frame", {
                Size = UDim2.new(1, 0, 0, height),
                BackgroundColor3 = THEME.Glass, BorderSizePixel = 0, Parent = parent,
        })
        corner(s, radius)
        create("UIGradient", {
                Rotation = 90,
                Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.9),
                        NumberSequenceKeypoint.new(1, 1),
                }),
                Parent = s,
        })
        return s
end
local function pressScale(btn, dip)
        local s = create("UIScale", { Scale = 1, Parent = btn })
        btn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        tw(s, 0.08, { Scale = dip }, Enum.EasingStyle.Quad):Play()
                end
        end)
        btn.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        tw(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Elastic):Play()
                end
        end)
        return s
end
local function pressTint(row, tint, pressT, baseT)
        row.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        tw(tint, 0.08, { BackgroundTransparency = pressT }, Enum.EasingStyle.Quad):Play()
                end
        end)
        row.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        tw(tint, 0.25, { BackgroundTransparency = baseT or 0 }, Enum.EasingStyle.Quad):Play()
                end
        end)
end

-- ============================================================
-- [11] SCREENGUI + PARRY SHOCKWAVE LAYER + MAIN SHELL
-- ============================================================
bootSay("[BYAK 3/6] building UI…")
screenGui = create("ScreenGui", {
        Name = "ByakuganRS_HUD",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
})
local parentedOk = pcall(function()
        screenGui.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not parentedOk then
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui", 10)
end
bootSay("[BYAK 4/6] HUD shell…")

-- full-screen edge glow that flashes on every parry (toggleable)
local fxGroup = create("CanvasGroup", {
        Name = "ParryShockwave", Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        GroupTransparency = 1, ZIndex = 5, Parent = screenGui,
})
do
        local edges = {
                { Size = UDim2.new(1, 0, 0, 110), Pos = UDim2.new(0, 0, 0, 0),   Rot = 90 },
                { Size = UDim2.new(1, 0, 0, 110), Pos = UDim2.new(0, 0, 1, -110), Rot = 270 },
                { Size = UDim2.new(0, 90, 1, 0),  Pos = UDim2.new(0, 0, 0, 0),   Rot = 0 },
                { Size = UDim2.new(0, 90, 1, 0),  Pos = UDim2.new(1, -90, 0, 0), Rot = 180 },
        }
        for _, e in ipairs(edges) do
                create("Frame", {
                        Size = e.Size, Position = e.Pos, BackgroundColor3 = THEME.Glass,
                        BackgroundTransparency = 0.72, BorderSizePixel = 0, Parent = fxGroup,
                        ZIndex = 5,
                }, {
                        create("UIGradient", {
                                Rotation = e.Rot,
                                Transparency = NumberSequence.new({
                                        NumberSequenceKeypoint.new(0, 0.35),
                                        NumberSequenceKeypoint.new(1, 1),
                                }),
                        }),
                })
        end
end

local WIN_W = 302
local winH = 560 -- final height computed after rows are built
local HEADER_H, FOOTER_H = 52, 26

local main = create("CanvasGroup", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 14),
        Size = UDim2.fromOffset(WIN_W, winH),
        BackgroundColor3 = THEME.Carbon,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 1,
        Visible = false,
        Parent = screenGui,
})
corner(main, 20)
stroke(main, THEME.RedGlow, 2, 0.9) -- v26.2: slimmer halo, minimal
local mainStroke = stroke(main, THEME.Red, 1.4, 0.15)
local strokeGradient = create("UIGradient", {
        Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, THEME.Red),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(64, 64, 74)),
                ColorSequenceKeypoint.new(1, THEME.Red),
        }),
        Parent = mainStroke,
})
local strokeGradTween = tw(strokeGradient, 4, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
strokeGradTween:Play()
sheen(main, 24, 20)
local winScale = create("UIScale", { Scale = 1, Parent = main })

-- ambient red wash drifting behind the glass
local ambient = create("Frame", {
        Name = "Ambient", Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = THEME.Red, BackgroundTransparency = 1,
        BorderSizePixel = 0, Parent = main, ZIndex = 0,
})
local ambientGrad = create("UIGradient", {
        Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, THEME.Red),
                ColorSequenceKeypoint.new(0.55, THEME.Carbon),
                ColorSequenceKeypoint.new(1, THEME.Carbon),
        }),
        Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.93),
                NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 35, Parent = ambient,
})
local ambientGradTween = tw(ambientGrad, 16, { Rotation = 395 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
ambientGradTween:Play()

-- fit to phone screens
local fitFactor, curWinScale = 1, 1
local function applyFit()
        local cam = Workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1200, 800)
        fitFactor = math.clamp(math.min((vp.X - 16) / WIN_W, (vp.Y - 16) / winH), 0.5, 1)
        winScale.Scale = fitFactor * curWinScale
end
applyFit()
pcall(function()
        local cam0 = Workspace.CurrentCamera
        if cam0 then
                cam0:GetPropertyChangedSignal("ViewportSize"):Connect(applyFit)
        end
end)
local function winScaleTo(target, time, style)
        curWinScale = target
        return TweenService:Create(winScale,
                TweenInfo.new(time or 0.3, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Scale = fitFactor * target })
end

-- header (drag zone) + RS badge + liquid sweep
local header = create("TextButton", {
        Name = "Header", Size = UDim2.new(1, 0, 0, HEADER_H),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = main, ZIndex = 2,
})
local badgeScale = create("UIScale", { Scale = 0, Parent = header })
local badge = create("TextLabel", {
        Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 12, 0.5, -17),
        BackgroundColor3 = THEME.Red, Text = "RS",
        Font = Enum.Font.GothamBlack, TextSize = 14,
        TextColor3 = Color3.fromRGB(255, 255, 255), Parent = header, ZIndex = 3,
})
corner(badge, 9)
stroke(badge, THEME.RedGlow, 1, 0.5)
create("TextLabel", {
        Size = UDim2.new(1, -120, 0, 17), Position = UDim2.new(0, 56, 0, 9),
        BackgroundTransparency = 1, RichText = true,
        Text = 'AUDI RS <font color="#FF2D46">//</font> BYAKUGAN',
        Font = Enum.Font.GothamBlack, TextSize = 15,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header, ZIndex = 3,
})
create("TextLabel", {
        Size = UDim2.new(1, -120, 0, 12), Position = UDim2.new(0, 56, 0, 27),
        BackgroundTransparency = 1,
        Text = "RS27.4 · NEURA · PREDICT · PERF",
        Font = Enum.Font.GothamBold, TextSize = 8,
        TextColor3 = THEME.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header, ZIndex = 3,
})

-- liquid sheen that sweeps across the header every few seconds
local sweep = create("Frame", {
        Size = UDim2.new(0, 70, 1, 0), Position = UDim2.new(0, -90, 0, 0),
        BackgroundColor3 = THEME.Glass, BackgroundTransparency = 0.86,
        BorderSizePixel = 0, Parent = header, ZIndex = 2,
})
create("UIGradient", {
        Rotation = 0,
        Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.35),
                NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = sweep,
})
task.spawn(function()
        task.wait(2.5)
        while uiAlive and sweep.Parent do
                if perfMode then sweep.Visible = false task.wait(1)
                else
                sweep.Visible = true
                sweep.Position = UDim2.new(0, -90, 0, 0)
                local t = tw(sweep, 1.1, { Position = UDim2.new(1, 20, 0, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                t:Play()
                local done = false
                t.Completed:Connect(function() done = true end)
                while not done and uiAlive and sweep.Parent do task.wait(0.1) end
                task.wait(6)
                end
        end
end)

local function ghostButton(symbol, xOffset)
        local btn = create("TextButton", {
                Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, xOffset, 0, 13),
                BackgroundColor3 = THEME.Panel, Text = symbol,
                Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = THEME.TextDim,
                AutoButtonColor = false, Parent = header, ZIndex = 3,
        })
        corner(btn, 8)
        stroke(btn, THEME.Stroke, 1, 0)
        pressScale(btn, 0.82)
        return btn
end
local minimizeBtn = ghostButton("–", -64)
local closeBtn = ghostButton("×", -34)

create("Frame", {
        Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, 60),
        BackgroundColor3 = THEME.Stroke, BackgroundTransparency = 0.4,
        BorderSizePixel = 0, Parent = main,
})

-- status row (old RS HUD: STANDBY / PARRY ENGAGED)
local statusDot = create("Frame", {
        Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 18, 0, 74),
        BackgroundColor3 = THEME.TextDim, BorderSizePixel = 0, Parent = main,
})
fullCorner(statusDot)
local statusText = create("TextLabel", {
        Size = UDim2.new(0, 220, 0, 20), Position = UDim2.new(0, 36, 0, 69),
        BackgroundTransparency = 1, Text = "STANDBY",
        Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = THEME.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = main,
})
local statusScale = create("UIScale", { Scale = 1, Parent = statusText })
local pulseTween = TweenService:Create(statusDot,
        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Size = UDim2.fromOffset(16, 16) })

local function setStatus(active)
        if active then
                statusText.Text = "PARRY ENGAGED"
                statusText.TextColor3 = THEME.RedGlow
                statusDot.BackgroundColor3 = THEME.RedGlow
                elasticPop(statusScale, 1.22)
                if not pulseTween.Playing then pulseTween:Play() end
        else
                statusText.Text = "STANDBY"
                statusText.TextColor3 = THEME.TextDim
                statusDot.BackgroundColor3 = THEME.TextDim
                pulseTween:Cancel()
                statusDot.Size = UDim2.fromOffset(10, 10)
        end
end

-- PERF MODE UI GATE — freezes every cosmetic infinite animation
-- (rotating strokes, drifting wash, header sweep, dot pulse).
-- These loops re-render every frame on mobile and were the main
-- source of HUD lag.
applyPerfUI = function()
        local on = perfMode
        if strokeGradTween then
                if on then strokeGradTween:Pause() else strokeGradTween:Play() end
        end
        if ambientGradTween then
                if on then ambientGradTween:Pause() else ambientGradTween:Play() end
        end
        if pulseTween then
                if on then pulseTween:Pause()
                elseif isRunning and not pulseTween.Playing then pulseTween:Play() end
        end
        if sweep and sweep.Parent then sweep.Visible = not on end
end

-- ============================================================
-- [12] ROW BUILDERS — spring toggles + fluid steppers
-- ============================================================
local animRows = {} -- registered rows -> staggered cascade on open
local rowY = 104 -- cursor shared with the wiring section
local function rowSlot(h)
        local y = rowY
        rowY = rowY + h + 6
        return y
end

local function makeSwitchRow(labelText, initial, callback)
        local y = rowSlot(40)
        local row = create("TextButton", {
                Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, y),
                BackgroundColor3 = THEME.PanelDark, Text = "",
                AutoButtonColor = false, Parent = main, ZIndex = 2,
        })
        corner(row, 10)
        local rowStroke = stroke(row, THEME.Stroke, 1, 0)
        pressTint(row, row, 0.85)

        create("TextLabel", {
                Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 12, 0, 0),
                BackgroundTransparency = 1, Text = labelText,
                Font = Enum.Font.GothamBold, TextSize = 13,
                TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row, ZIndex = 3,
        })

        local track = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(42, 22),
                BackgroundColor3 = initial and THEME.Red or THEME.Panel,
                Parent = row, ZIndex = 3,
        })
        fullCorner(track)
        local trackStroke = stroke(track, initial and THEME.RedGlow or THEME.Stroke, 1, 0)
        local glowRing = stroke(track, THEME.RedGlow, 3, 1) -- flash ring on enable
        local knobScale = create("UIScale", { Scale = 1, Parent = track })
        local knob = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(16, 16),
                Position = UDim2.new(0, initial and 31 or 11, 0.5, 0),
                BackgroundColor3 = initial and Color3.fromRGB(255, 255, 255) or THEME.TextDim,
                Parent = track, ZIndex = 4,
        })
        fullCorner(knob)

        local state = initial
        local function render(instant)
                local info = instant and TweenInfo.new(0)
                        or TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                TweenService:Create(knob, info, {
                        Position = state and UDim2.new(0, 31, 0.5, 0) or UDim2.new(0, 11, 0.5, 0),
                        BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or THEME.TextDim,
                }):Play()
                TweenService:Create(track, info, {
                        BackgroundColor3 = state and THEME.Red or THEME.Panel,
                }):Play()
                TweenService:Create(trackStroke, info, {
                        Color = state and THEME.RedGlow or THEME.Stroke,
                }):Play()
                TweenService:Create(rowStroke, info, {
                        Color = state and THEME.Red or THEME.Stroke,
                        Transparency = state and 0.1 or 0,
                }):Play()
        end
        render(true)

        row.Activated:Connect(function()
                state = not state
                render(false)
                -- iOS squish: knob squeezes then springs back
                if state then
                        glowRing.Transparency = 0.1
                        tw(glowRing, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad):Play()
                end
                elasticPop(knobScale, state and 1.28 or 1.16)
                callback(state)
        end)
        table.insert(animRows, row)
        return row
end

-- RS instrument-style stepper: "< VALUE >" with slide-bounce swap
local function makeStepperRow(labelText, options, startIndex, onPick)
        local y = rowSlot(36)
        local row = create("TextButton", {
                Size = UDim2.new(1, -24, 0, 36), Position = UDim2.new(0, 12, 0, y),
                BackgroundColor3 = THEME.PanelDark, Text = "",
                AutoButtonColor = false, Parent = main, ZIndex = 2,
        })
        corner(row, 10)
        local rowStroke = stroke(row, THEME.Stroke, 1, 0)
        pressTint(row, row, 0.85)
        create("TextLabel", {
                Size = UDim2.new(0, 110, 1, 0), Position = UDim2.new(0, 12, 0, 0),
                BackgroundTransparency = 1, Text = labelText,
                Font = Enum.Font.GothamBold, TextSize = 12,
                TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row, ZIndex = 3,
        })

        local holder = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0),
                Size = UDim2.new(0, 132, 0, 20), BackgroundTransparency = 1,
                ClipsDescendants = true, Parent = row, ZIndex = 3,
        })
        local valueLabel = create("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0),
                BackgroundTransparency = 1, Text = options[startIndex],
                Font = Enum.Font.GothamBlack, TextSize = 12,
                TextColor3 = THEME.RedGlow, TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = holder, ZIndex = 4,
        })

        local function arrow(xOffset, symbol)
                local b = create("TextButton", {
                        Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, xOffset, 0.5, -12),
                        BackgroundColor3 = THEME.Panel, Text = symbol,
                        Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = THEME.TextDim,
                        AutoButtonColor = false, Parent = row, ZIndex = 4,
                })
                corner(b, 7)
                pressScale(b, 0.8)
                return b
        end
        local leftBtn = arrow(-62, "<")
        local rightBtn = arrow(-32, ">")

        local idx = startIndex
        local swapToken = 0
        local function animateTo(newText, dir)
                swapToken = swapToken + 1
                local tk = swapToken
                task.spawn(function()
                        local out = tw(valueLabel, 0.1,
                                { TextTransparency = 1, Position = UDim2.new(0, dir * -22, 0, 0) },
                                Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                        out:Play()
                        out.Completed:Wait()
                        if tk ~= swapToken or not valueLabel.Parent then return end
                        valueLabel.Text = newText
                        valueLabel.Position = UDim2.new(0, dir * 22, 0, 0)
                        tw(valueLabel, 0.32, { TextTransparency = 0, Position = UDim2.new(0, 0, 0, 0) },
                                Enum.EasingStyle.Back):Play()
                end)
        end
        local function flashArrow(btn)
                btn.TextColor3 = THEME.RedGlow
                tw(btn, 0.4, { TextColor3 = THEME.TextDim }, Enum.EasingStyle.Quad):Play()
        end
        local function bumpRow()
                rowStroke.Color = THEME.Red
                tw(rowStroke, 0.5, { Color = THEME.Stroke }, Enum.EasingStyle.Quad):Play()
        end
        local function step(dir)
                idx = ((idx - 1 + dir) % #options) + 1
                animateTo(options[idx], dir)
                onPick(idx, options[idx])
                bumpRow()
        end
        leftBtn.Activated:Connect(function() flashArrow(leftBtn) step(-1) end)
        rightBtn.Activated:Connect(function() flashArrow(rightBtn) step(1) end)
        row.Activated:Connect(function() step(1) end)
        -- v27.4: the boot mode-chooser keeps this row's label (and
        -- step index) in sync if it picks a mode before the menu
        -- stepper is ever touched
        if labelText == "PARRY MODE" then
                parryModeSync = function(txt, wantIdx)
                        if wantIdx then idx = wantIdx end
                        valueLabel.Text = txt
                end
        end
        table.insert(animRows, row)
        return row
end

-- ============================================================
-- [13] DYNAMIC ISLAND — the pill + BYAKU-BOT ascii mascot
-- ============================================================
local pill = create("CanvasGroup", {
        Name = "Island", AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(118, 34),
        BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 0.12,
        BorderSizePixel = 0, ClipsDescendants = true, GroupTransparency = 1,
        Visible = false, Parent = screenGui,
})
fullCorner(pill)
stroke(pill, THEME.Glass, 1, 0.82)
sheen(pill, 10, 17)
local pillScale = create("UIScale", { Scale = 1, Parent = pill })

-- BYAKU-BOT — tiny ascii robot living in the island. Blinks,
-- smiles, and jumps up every now and then. Pure Text swaps, so
-- it costs nothing even at 60 fps.
local bot = create("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.fromOffset(26, 16), Position = UDim2.new(0, 8, 0.5, -1),
        BackgroundTransparency = 1, Text = "^_^",
        Font = Enum.Font.Code, TextSize = 12,
        TextColor3 = THEME.TextDim, TextXAlignment = Enum.TextXAlignment.Center,
        Parent = pill,
})
local botScale = create("UIScale", { Scale = 1, Parent = bot })
do
        local BOT_IDLE, BOT_BLINK, BOT_JOY, BOT_JUMP = "^_^", "-_-", "^o^", "\\o/"
        local lastBlink = os.clock()
        local nextJump  = os.clock() + math.random(5, 10)
        local jumping   = false
        task.spawn(function()
                while uiAlive do
                        if not bot.Parent then break end
                        local now = os.clock()
                        if not jumping and now >= nextJump then
                                jumping = true
                                nextJump = now + math.random(7, 14)
                                -- squash -> leap -> elastic land -> joy
                                tw(botScale, 0.1, { Scale = 1.2 }, Enum.EasingStyle.Back):Play()
                                bot.Text = BOT_IDLE
                                task.wait(0.12)
                                if not bot.Parent then break end
                                bot.Text = BOT_JUMP
                                tw(bot, 0.32, { Position = UDim2.new(0, 8, 0.5, -9) },
                                        Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
                                task.wait(0.34)
                                if not bot.Parent then break end
                                tw(bot, 0.45, { Position = UDim2.new(0, 8, 0.5, -1) },
                                        Enum.EasingStyle.Elastic, Enum.EasingDirection.Out):Play()
                                task.wait(0.24)
                                if not bot.Parent then break end
                                bot.Text = BOT_JOY
                                task.wait(0.55)
                                if not bot.Parent then break end
                                tw(botScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Elastic):Play()
                                bot.Text = BOT_IDLE
                                jumping = false
                        elseif not jumping and now - lastBlink >= 3.8 then
                                lastBlink = now
                                bot.Text = BOT_BLINK
                                task.wait(0.14)
                                if not bot.Parent then break end
                                bot.Text = BOT_IDLE
                        end
                        task.wait(0.1)
                end
        end)
end

local pillLabel = create("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0), Position = UDim2.new(0, 36, 0, 0),
        BackgroundTransparency = 1, Text = "Idle",
        Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = pill,
})
local pillDot = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(6, 6),
        Position = UDim2.new(1, -10, 0.5, 0),
        BackgroundColor3 = THEME.TextDim, BorderSizePixel = 0, Parent = pill,
})
fullCorner(pillDot)
local pillButton = create("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = pill,
})

-- parry shockwave ring around the island
local pillRing = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 29),
        Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 4, Parent = screenGui,
})
fullCorner(pillRing)
local pillRingStroke = stroke(pillRing, THEME.Glass, 2.5, 1)

local popTween = nil
local function islandPop(strength)
        if not pillScale.Parent then return end
        if popTween then popTween:Cancel() end
        pillScale.Scale = strength
        popTween = tw(pillScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
        popTween:Play()
end
local wiggleToken = 0
local function islandWiggle()
        if perfMode then return end -- v26.2: no cosmetic churn in perf
        if not pill.Parent then return end
        wiggleToken = wiggleToken + 1
        local token = wiggleToken
        task.spawn(function()
                for _, r in ipairs({ -3.5, 3, -2, 1, 0 }) do
                        if token ~= wiggleToken or not pill.Parent then return end
                        local t = tw(pill, 0.08, { Rotation = r }, Enum.EasingStyle.Quad)
                        t:Play()
                        t.Completed:Wait()
                end
        end)
end

-- THE SHOCKWAVE — v26.2: minimal WHITE pulse (red removed),
-- skipped entirely in perf mode
fxBurst = function()
        if not fxEnabled or perfMode then return end
        if fxGroup and fxGroup.Parent then
                fxGroup.GroupTransparency = 0.55
                tw(fxGroup, 0.26, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
        end
        if pillRing and pillRing.Parent then
                pillRing.Size = UDim2.fromOffset(34, 34)
                pillRingStroke.Transparency = 0.3
                tw(pillRing, 0.5, { Size = UDim2.fromOffset(120, 120) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
                tw(pillRingStroke, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
        end
end

-- ============================================================
-- [14] OPEN / CLOSE / MINIMIZE — every move bounces
-- ============================================================
local winOpen = false
local function openMain()
        if winOpen then return end
        winOpen = true
        main.Visible = true
        winScale.Scale = fitFactor * 0.7
        main.GroupTransparency = 1
        main.Rotation = -2.5
        tw(main, 0.3, { GroupTransparency = 0 }):Play()
        winScaleTo(1, 0.5, Enum.EasingStyle.Back):Play()
        tw(main, 0.65, { Rotation = 0 }, Enum.EasingStyle.Elastic):Play()
        elasticPop(badgeScale, 1.3) -- RS badge springs in on every open
        islandPop(1.14)
        islandWiggle()
        -- v26.2: iOS list cascade — rows drift up with stagger
        for i, r in ipairs(animRows) do
                if r.Parent then
                        local bp = r.Position
                        r.Position = UDim2.new(bp.X.Scale, bp.X.Offset,
                                bp.Y.Scale, bp.Y.Offset + 18)
                        task.delay(i * 0.032, function()
                                if r.Parent then
                                        tw(r, 0.5, { Position = bp },
                                                Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()
                                end
                        end)
                end
        end
end
local function closeMain()
        if not winOpen then return end
        winOpen = false
        winScaleTo(0.8, 0.2):Play()
        local out = tw(main, 0.2, { GroupTransparency = 1, Rotation = -1.5 },
                Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out:Play()
        out.Completed:Connect(function()
                if not winOpen and main.Parent then main.Visible = false end
        end)
end
pillButton.Activated:Connect(function()
        islandPop(1.12)
        if winOpen then closeMain() else openMain() end
end)
minimizeBtn.Activated:Connect(function() closeMain() end)
closeBtn.Activated:Connect(function()
        if unloadFn then unloadFn() end
end)

-- dragging (mouse + touch) with fluid tilt settle
do
        local dragging = false
        local dragStart = nil
        local startPos = nil
        header.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        dragStart = input.Position
                        startPos = main.Position
                        input.Changed:Connect(function()
                                if input.UserInputState == Enum.UserInputState.End then
                                        dragging = false
                                        if main.Parent then
                                                tw(main, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic):Play()
                                        end
                                end
                        end)
                end
        end)
        UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        local delta = input.Position - dragStart
                        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                        if main.Parent then
                                main.Rotation = math.clamp(delta.X * 0.03, -4, 4)
                        end
                end
        end)
        UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = false
                end
        end)
end

-- ============================================================
-- [15] BOOT CARD — RS ignition with springs
-- ============================================================
local bootCard = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(300, 190), BackgroundColor3 = THEME.Carbon,
        BackgroundTransparency = 0.08, BorderSizePixel = 0, GroupTransparency = 1,
        Visible = true, ZIndex = 50, Parent = screenGui,
})
corner(bootCard, 24)
stroke(bootCard, THEME.RedGlow, 1.4, 0.5)
sheen(bootCard, 20, 24)
local bootScale = create("UIScale", { Scale = 0.7, Parent = bootCard })
local bootBadgeScale = create("UIScale", { Scale = 0, Parent = bootCard })
local bootBadge = create("TextLabel", {
        Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, -23, 0, 18),
        BackgroundColor3 = THEME.Red, Text = "RS",
        Font = Enum.Font.GothamBlack, TextSize = 18,
        TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 51, Parent = bootCard,
})
corner(bootBadge, 12)
stroke(bootBadge, THEME.RedGlow, 1.5, 0.35)
local bootTitle = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 70),
        BackgroundTransparency = 1, Text = "BYAKUGAN",
        Font = Enum.Font.GothamBlack, TextSize = 22,
        TextColor3 = THEME.Text, TextTransparency = 1, ZIndex = 51, Parent = bootCard,
})
local bootSub = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 96),
        BackgroundTransparency = 1, Text = "AUDI RS × iOS 26 FLUID",
        Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = THEME.RedGlow, TextTransparency = 1, ZIndex = 51, Parent = bootCard,
})
local barBg = create("Frame", {
        Size = UDim2.new(1, -48, 0, 6), Position = UDim2.new(0, 24, 0, 122),
        BackgroundColor3 = Color3.fromRGB(40, 40, 46), BorderSizePixel = 0, ZIndex = 51, Parent = bootCard,
})
corner(barBg, 3)
local barFill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = THEME.RedGlow,
        BorderSizePixel = 0, ZIndex = 51, Parent = barBg,
})
corner(barFill, 3)
local bootCaption = create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 12), Position = UDim2.new(0, 12, 0, 138),
        BackgroundTransparency = 1, Text = "Igniting quattro core…",
        Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = THEME.TextDim, ZIndex = 51, Parent = bootCard,
})
local bootPct = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 156),
        BackgroundTransparency = 1, Text = "0%",
        Font = Enum.Font.GothamBlack, TextSize = 11,
        TextColor3 = THEME.Text, ZIndex = 51, Parent = bootCard,
})

-- ============================================================
-- [15b] HIGH PERFORMANCE MODE — strips the 3D fat, restorable
-- ============================================================
-- Client-side only: plastic-ify parts, kill decals/textures/
-- particles/beams/trails/highlights/shadows, drop quality level,
-- flatten terrain fx. Originals are snapshotted and restored on
-- toggle-off. New descendants (round resets) are stripped too.
local perfBackup = {}
local perfConn   = nil
local perfGlobals = {}
local PERF_KEEP_MAT = { Neon = true, ForceField = true }

local function perfStrip(inst)
        if perfBackup[inst] then return end
        if inst:IsA("Terrain") then return end -- Terrain inherits BasePart; never touch it
        pcall(function()
                if inst:IsA("BasePart") then
                        perfBackup[inst] = {
                                mat = inst.Material, shadow = inst.CastShadow,
                                refl = inst.Reflectance,
                        }
                        if not PERF_KEEP_MAT[inst.Material] then
                                inst.Material = Enum.Material.SmoothPlastic
                        end
                        inst.CastShadow = false
                        inst.Reflectance = 0
                elseif inst:IsA("Decal") or inst:IsA("Texture") then
                        perfBackup[inst] = { tr = inst.Transparency }
                        inst.Transparency = 1
                elseif inst:IsA("ParticleEmitter") or inst:IsA("Fire")
                        or inst:IsA("Smoke") or inst:IsA("Sparkles")
                        or inst:IsA("Trail") or inst:IsA("Beam") then
                        perfBackup[inst] = { en = inst.Enabled }
                        inst.Enabled = false
                elseif inst:IsA("Highlight") then
                        perfBackup[inst] = { en = inst.Enabled }
                        inst.Enabled = false
                elseif inst:IsA("Explosion") then
                        perfBackup[inst] = { vis = inst.Visible }
                        inst.Visible = false
                else
                        return
                end
        end)
end

local function perfRestoreAll()
        if perfConn then perfConn:Disconnect() perfConn = nil end
        for inst, snap in pairs(perfBackup) do
                pcall(function()
                        if inst and inst.Parent then
                                if snap.mat ~= nil then
                                        inst.Material = snap.mat
                                        inst.CastShadow = snap.shadow
                                        inst.Reflectance = snap.refl
                                end
                                if snap.tr ~= nil then inst.Transparency = snap.tr end
                                if snap.en ~= nil then inst.Enabled = snap.en end
                                if snap.vis ~= nil then inst.Visible = snap.vis end
                        end
                end)
                perfBackup[inst] = nil
        end
end

local function perfApplyWorld(on)
        local Lighting = game:GetService("Lighting")
        if on then
                perfGlobals = {}
                pcall(function() perfGlobals.shadows = Lighting.GlobalShadows end)
                pcall(function() perfGlobals.diff = Lighting.EnvironmentDiffuseScale end)
                pcall(function() perfGlobals.spec = Lighting.EnvironmentSpecularScale end)
                pcall(function()
                        local terr = Workspace.Terrain
                        perfGlobals.deco = terr.Decoration
                        perfGlobals.wsize = terr.WaterWaveSize
                        perfGlobals.wspeed = terr.WaterWaveSpeed
                        perfGlobals.wrefl = terr.WaterReflectance
                end)
                pcall(function() Lighting.GlobalShadows = false end)
                pcall(function() Lighting.EnvironmentDiffuseScale = 0 end)
                pcall(function() Lighting.EnvironmentSpecularScale = 0 end)
                pcall(function()
                        local terr = Workspace.Terrain
                        terr.Decoration = false
                        terr.WaterWaveSize = 0
                        terr.WaterWaveSpeed = 0
                        terr.WaterReflectance = 0
                end)
                pcall(function()
                        settings().Rendering.QualityLevel = Enum.QualityLevel.Level1
                end)
                for _, d in ipairs(Workspace:GetDescendants()) do perfStrip(d) end
                perfConn = Workspace.DescendantAdded:Connect(function(d)
                        task.defer(perfStrip, d)
                end)
        else
                perfRestoreAll()
                pcall(function() Lighting.GlobalShadows = perfGlobals.shadows end)
                pcall(function() Lighting.EnvironmentDiffuseScale = perfGlobals.diff end)
                pcall(function() Lighting.EnvironmentSpecularScale = perfGlobals.spec end)
                pcall(function()
                        local terr = Workspace.Terrain
                        terr.Decoration = perfGlobals.deco
                        terr.WaterWaveSize = perfGlobals.wsize
                        terr.WaterWaveSpeed = perfGlobals.wspeed
                        terr.WaterReflectance = perfGlobals.wrefl
                end)
                pcall(function()
                        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
                end)
        end
end

-- ============================================================
-- [16] WIRE ROWS TO THE ENGINE
-- ============================================================
makeSwitchRow("AUTO PARRY", isRunning, function(v)
        isRunning = v
        setStatus(v)
        pushStatus(v and "Parry on" or "Parry off", 1)
end)

makeSwitchRow("AUTO SPAM <13", autoSpamEnabled, function(v)
        autoSpamEnabled = v
        if not v then
                spamActive = false
                spamHold = false
        end
        pushStatus(v and "Auto spam armed" or "Auto spam off", 1.2)
end)

makeSwitchRow("PARRY SHOCKWAVE", fxEnabled, function(v)
        fxEnabled = v
end)

makeSwitchRow("BYAKUGAN AURA", auraEnabled, function(v)
        auraEnabled = v
        local char = LocalPlayer.Character
        local hl = char and char:FindFirstChild("ByakuganAura")
        if hl then hl.Enabled = v end
end)

makeSwitchRow("SERVER DOT", dotEnabled, function(v)
        dotEnabled = v
        serverBallDot.Transparency = v and 0 or 1
end)

makeSwitchRow("PERF MODE", perfMode, function(v)
        perfMode = v
        xpcall(function() perfApplyWorld(v) end, function() end)
        if applyPerfUI then xpcall(function() applyPerfUI() end, function() end) end
        pushStatus(v and "Perf mode ON" or "Perf mode off", 1.4)
        if v then islandPop(1.1) end
end)

-- v27.4: which trigger geometry fires the parry — the velocity-
-- scaled sphere or the classic TTI timer. Also asked at boot.
makeStepperRow("PARRY MODE",
        { "SPHERE", "TIMER" }, parryMode == "Timer" and 2 or 1,
        function(i, opt)
                parryMode = (opt == "TIMER") and "Timer" or "Sphere"
                if opt == "TIMER" then sphereVisDestroy() end
                pushStatus(opt .. " parry trigger", 1.2)
                islandPop(1.2)
        end)

makeStepperRow("PARRY METHOD",
        { "Auto (Smart)", "Hook Replay", "Button", "Firesignal", "Remote" }, 1,
        function(i, opt)
                parryMethod = ({ "Auto", "Hook", "Button", "Signal", "Remote" })[i]
                pushStatus("Method: " .. opt, 1.2)
        end)

makeStepperRow("CURVE MODE",
        { "Camera", "Random", "Accelerated", "Backwards", "Slow", "High", "Normal", "Speed", "Down", "Left", "Right" }, 1,
        function(i, opt)
                parryCurve = opt
                pushStatus("Curve: " .. opt, 1.2)
        end)

makeStepperRow("PREDICT",
        { "OFF", "25%", "50%", "75%", "100%" }, 1,
        function(i, opt)
                predictPct = ({ 0, 0.25, 0.5, 0.75, 1 })[i]
                pushStatus(opt == "OFF" and "Predict off"
                        or "Predict lead " .. opt, 1.2)
        end)

makeStepperRow("ROTATION",
        { "ON", "OFF" }, 1,
        function(i, opt)
                rotCurveOn = (i == 1)
                pushStatus(opt == "ON" and "Rotation curve on"
                        or "Rotation curve off", 1.2)
        end)

makeStepperRow("NEURA",
        { "ON", "OFF" }, 1,
        function(i, opt)
                neuraOn = (i == 1)
                pushStatus(opt == "ON" and "Neura net on — learning live"
                        or "Neura net off", 1.2)
        end)

-- ============================================================
-- [16b] BOOT MODE CHOOSER (v27.4 user spec) — "sphere mode or
-- timer mode?" asked right after boot; whichever the user picks
-- is used. Untouched for 9 s keeps the default SPHERE. The menu
-- PARRY MODE row re-chooses any time (kept in sync both ways).
-- ============================================================
task.delay(2.4, function()
        local picked = false
        local card = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 58),
                Size = UDim2.fromOffset(300, 132),
                BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.06,
                BorderSizePixel = 0, Parent = screenGui, ZIndex = 60,
        })
        corner(card, 18)
        stroke(card, THEME.Red, 1.4, 0.35)
        create("TextLabel", {
                Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 10),
                BackgroundTransparency = 1, Text = "CHOOSE PARRY MODE",
                Font = Enum.Font.GothamBlack, TextSize = 16,
                TextColor3 = THEME.Text, Parent = card, ZIndex = 61,
        })
        create("TextLabel", {
                Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 40),
                BackgroundTransparency = 1, TextWrapped = true,
                Text = "SPHERE = velocity-scaled hitbox bubble (visible)\nTIMER = classic TTI send-lead window",
                Font = Enum.Font.Gotham, TextSize = 10,
                TextColor3 = THEME.TextDim, Parent = card, ZIndex = 61,
        })
        local function pickMode(xOff, label, mode)
                local b = create("TextButton", {
                        Size = UDim2.fromOffset(132, 44),
                        Position = UDim2.new(0, xOff, 1, -52),
                        BackgroundColor3 = mode == "Sphere" and THEME.Red
                                or THEME.PanelDark,
                        Text = label, Font = Enum.Font.GothamBlack,
                        TextSize = 13, TextColor3 = THEME.Text,
                        AutoButtonColor = false, Parent = card, ZIndex = 61,
                })
                corner(b, 12)
                pressScale(b, 0.9)
                b.Activated:Connect(function()
                        if picked then return end
                        picked = true
                        parryMode = mode
                        if mode ~= "Sphere" then sphereVisDestroy() end
                        if parryModeSync then
                                parryModeSync(mode == "Timer" and "TIMER" or "SPHERE",
                                        mode == "Timer" and 2 or 1)
                        end
                        pushStatus(mode .. " parry mode selected", 1.6)
                        islandPop(1.3)
                        fxBurst()
                        tw(card, 0.22, { Position = UDim2.new(0.5, 0, 0, -150) },
                                Enum.EasingStyle.Back, Enum.EasingDirection.In):Play()
                        task.delay(0.24, function() card:Destroy() end)
                end)
                return b
        end
        pickMode(12, "SPHERE", "Sphere")
        pickMode(156, "TIMER", "Timer")
        -- decide-later: keep the default (SPHERE) and slide away
        task.delay(9, function()
                if not picked and card.Parent then
                        tw(card, 0.3, { Position = UDim2.new(0.5, 0, 0, -150) },
                                Enum.EasingStyle.Quad, Enum.EasingDirection.In):Play()
                        task.delay(0.32, function() card:Destroy() end)
                end
        end)
end)

-- ============================================================
-- [17] LIVE STATS STRIP + DIAGNOSTICS + FOOTER
-- ============================================================
local statsY = rowY + 2
rowY = statsY + 54 + 6
local statsPanel = create("Frame", {
        Size = UDim2.new(1, -24, 0, 54), Position = UDim2.new(0, 12, 0, statsY),
        BackgroundColor3 = THEME.PanelDark, BorderSizePixel = 0, Parent = main,
})
corner(statsPanel, 10)
stroke(statsPanel, THEME.Stroke, 1, 0)

local function statColumn(index, caption)
        local col = create("Frame", {
                Size = UDim2.new(1 / 4, 0, 1, 0), Position = UDim2.new((index - 1) / 4, 0, 0, 0),
                BackgroundTransparency = 1, Parent = statsPanel,
        })
        if index > 1 then
                create("Frame", {
                        Size = UDim2.new(0, 1, 1, -16), Position = UDim2.new(0, 0, 0, 8),
                        BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0, Parent = col,
                })
        end
        local value = create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 8),
                BackgroundTransparency = 1, Text = "--",
                Font = Enum.Font.GothamBlack, TextSize = 14,
                TextColor3 = THEME.Text, Parent = col,
        })
        create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 30),
                BackgroundTransparency = 1, Text = caption,
                Font = Enum.Font.GothamBold, TextSize = 8,
                TextColor3 = THEME.TextDim, Parent = col,
        })
        return value
end

local pingVal   = statColumn(1, "PING")
local speedVal  = statColumn(2, "BALL SPD")
local radiusVal = statColumn(3, "RADIUS")
local offsetVal = statColumn(4, "OFFSET")

-- diagnostics caption (token + capture state at a glance)
local diagCaption = create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 14), Position = UDim2.new(0, 12, 0, rowY),
        BackgroundTransparency = 1, Text = "PRY SCANNING · CAPTURE TAP BLOCK ONCE",
        Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = THEME.Amber,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = main,
})
rowY = rowY + 20

-- diagnostic actions
local btnRowY = rowSlot(32)
local function diagButton(label, half, cb)
        local b = create("TextButton", {
                Size = UDim2.new(0.5, -16, 0, 32),
                Position = UDim2.new(half, half == 0 and 12 or 4, 0, btnRowY),
                BackgroundColor3 = THEME.Panel, Text = label,
                Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = THEME.Text,
                AutoButtonColor = false, Parent = main,
        })
        corner(b, 9)
        stroke(b, THEME.Stroke, 1, 0)
        pressScale(b, 0.9)
        b.Activated:Connect(function()
                b.TextColor3 = THEME.RedGlow
                tw(b, 0.5, { TextColor3 = THEME.Text }, Enum.EasingStyle.Quad):Play()
                cb()
        end)
        return b
end
diagButton("RESCAN TOKEN", 0, function()
        local ok = findTokenFunction()
        pushStatus(ok and "Token found" or "Token missing", 1.4)
        if ok then islandPop(1.1) end
end)
diagButton("RE-ARM HOOK", 0.5, function()
        hookState.captured = nil
        hookState.capturedArgs = nil
        hookState.announced = false
        for k in pairs(hookStored) do hookStored[k] = nil end
        pushStatus("Capture reset", 1.4)
end)

-- footer
local footerY = rowY + 8
create("Frame", {
        Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, footerY - 5),
        BackgroundColor3 = THEME.Stroke, BackgroundTransparency = 0.5,
        BorderSizePixel = 0, Parent = main,
})
create("TextLabel", {
        Size = UDim2.new(0, 190, 0, 18), Position = UDim2.new(0, 14, 0, footerY),
        BackgroundTransparency = 1, Text = "QUATTRO LOGIC • RS26 FLUID",
        Font = Enum.Font.GothamBold, TextSize = 9,
        TextColor3 = THEME.TextDim, TextTransparency = 0.3,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = main,
})
local firesLabel = create("TextLabel", {
        Size = UDim2.new(0, 90, 0, 18), Position = UDim2.new(1, -14, 0, footerY),
        BackgroundTransparency = 1, Text = "fires 0",
        Font = Enum.Font.GothamBold, TextSize = 9,
        TextColor3 = THEME.TextDim, TextXAlignment = Enum.TextXAlignment.Right, Parent = main,
})

-- final window height -> re-fit to screen
winH = footerY + 30
main.Size = UDim2.fromOffset(WIN_W, winH)
applyFit()

-- full unload (old RS HUD close behavior)
unloadFn = function()
        isRunning = false
        uiAlive = false
        spamActive = false
        if renderConn then
                renderConn:Disconnect()
                renderConn = nil
        end
        for _, c in ipairs(liveConns) do
                pcall(function() c:Disconnect() end)
        end
        liveConns = {}
        -- restore the world if perf mode was stripping it
        if perfMode then
                perfMode = false
                xpcall(function() perfApplyWorld(false) end, function() end)
        end
        pcall(function() screenGui:Destroy() end)
        pcall(function() serverBallDot:Destroy() end)
        pcall(function() sphereVisDestroy() end)
        local char = LocalPlayer.Character
        local hl = char and char:FindFirstChild("ByakuganAura")
        if hl then hl:Destroy() end
end

-- ============================================================
-- [18] BOOT SEQUENCE — springs all the way in
-- ============================================================
local bootSettled = false -- v26.5: boot failsafe flag (watchdog below)
bootSay("[BYAK 5/6] boot animation…")
task.spawn(function()
        pcall(function()
                tw(bootCard, 0.4, { GroupTransparency = 0 }):Play()
                tw(bootScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back):Play()
                task.wait(0.18)
                tw(bootBadgeScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Elastic):Play()
                bootTitle.Position = UDim2.new(0, 0, 0, 78)
                tw(bootTitle, 0.45, { TextTransparency = 0, Position = UDim2.new(0, 0, 0, 70) }):Play()
                tw(bootSub, 0.55, { TextTransparency = 0 }):Play()
                task.wait(0.3)
                local captions = {
                        { 0.0,  "Igniting quattro core…" },
                        { 0.22, "Scanning GC for the PRY token…" },
                        { 0.48, "Hooking remotes for capture…" },
                        { 0.72, "Syncing player + client ping…" },
                        { 0.92, "Byakugan online." },
                }
                local progress, lastCap = 0, captions[1][2]
                while progress < 1 do
                        progress = math.min(1, progress + math.random(22, 60) / 1000)
                        local cap = captions[1][2]
                        for _, c in ipairs(captions) do
                                if progress >= c[1] then cap = c[2] end
                        end
                        if cap ~= lastCap then
                                lastCap = cap
                                bootCaption.Text = cap
                        end
                        bootPct.Text = tostring(math.floor(progress * 100)) .. "%"
                        tw(barFill, 0.3, { Size = UDim2.new(progress, 0, 1, 0) }, Enum.EasingStyle.Quart):Play()
                        task.wait(math.random(8, 18) / 100)
                end
                bootPct.Text = "100%"
                bootCaption.Text = "Ready — engage."
                findTokenFunction()
                task.wait(0.45)
                local out = tw(bootCard, 0.26, { GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tw(bootScale, 0.3, { Scale = 1.06 }, Enum.EasingStyle.Back, Enum.EasingDirection.In):Play()
                task.wait(0.12)
                tw(bootScale, 0.2, { Scale = 0.85 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In):Play()
                out:Play()
                out.Completed:Wait()
                pcall(function() bootCard:Destroy() end)
        end)
        -- v26.5: the post-animation tail is pcall'd — a nil pill or an
        -- island hiccup can no longer kill the "online" stage and leave
        -- the boot card / tracer stuck forever
        pcall(function()
                pill.Visible = true
                pill.GroupTransparency = 1
                tw(pill, 0.3, { GroupTransparency = 0 }):Play()
        end)
        bootSettled = true
        bootSay("[BYAK ✓] online — tracer clears in 30 s")
        pcall(function()
                islandPop(1.2)
                islandWiggle()
                pushStatus("Aura ignited", 2)
                if hookState.tokenOk then
                        pushStatus("PRY token found", 2.2)
                elseif not hookSupported then
                        pushStatus("No getgc — hook off", 2.4)
                end
                openMain()
        end)
end)

-- ============================================================
-- [18b] BOOT FAILSAFE (v26.5) — the boot can no longer stick. If the
--      animation thread died mid-way, 9 s after boot start the card
--      is force-destroyed and the HUD + main panel are force-opened.
--      No-op when boot settled normally.
-- ============================================================
task.delay(9, function()
        if bootSettled then return end
        bootSay("[BYAK ·] boot failsafe — forcing HUD online", true)
        pcall(function()
                if bootCard and bootCard.Parent then bootCard:Destroy() end
        end)
        pcall(function()
                if pill and not pill.Visible then
                        pill.Visible = true
                        pill.GroupTransparency = 1
                        tw(pill, 0.3, { GroupTransparency = 0 }):Play()
                end
        end)
        pcall(function() openMain() end)
        bootSettled = true
end)

-- ============================================================
-- [19] HUD REFRESH
-- ============================================================
local STATUS_COLORS = {
        ["Idle"]          = THEME.TextDim,
        ["Paused"]        = THEME.TextDim,
        ["Tracking"]      = THEME.TextDim,
        ["Not you"]       = THEME.TextDim,
        ["Waiting"]       = THEME.Amber,
        ["No ball"]       = THEME.Amber,
        ["No zoomies"]    = THEME.Amber,
        ["Getting close"] = THEME.Amber,
        ["Parried"]       = THEME.Good,
        ["Parrying"]      = THEME.RedGlow,
        ["Hook fired"]    = THEME.Text,
        ["Hook armed"]    = THEME.Good,
        ["Aura ignited"]  = THEME.Good,
        ["SPAM ENGAGED"]  = THEME.RedGlow,
        ["Spam released"] = THEME.TextDim,
        ["Parry on"]      = THEME.Good,
        ["Parry off"]     = THEME.TextDim,
}
local lastIslandText = nil
-- v26.2 anti-lag: HUD writes are cached — a label is only touched
-- when its value actually changed (every Roblox Text write forces
-- a re-layout; writing 6 labels at 8 Hz for nothing = mobile lag)
local hudTextCache, hudColCache = {}, {}
local function hudSet(label, key, text)
        if not label.Parent then return end
        if hudTextCache[key] ~= text then
                hudTextCache[key] = text
                label.Text = text
        end
end
local function hudCol(label, key, color)
        if not label.Parent then return end
        if hudColCache[key] ~= color then
                hudColCache[key] = color
                label.TextColor3 = color
        end
end
local function updateHUD(ball, root, pingSec)
        local txt = resolvedStatus()
        local col = STATUS_COLORS[txt] or THEME.Text
        if pillLabel.Parent then
                if txt ~= lastIslandText then
                        lastIslandText = txt
                        pillLabel.Text = txt
                        pillDot.BackgroundColor3 = col
                        pillLabel.TextColor3 = txt == "Idle" and THEME.TextDim or THEME.Text
                        if txt ~= "Idle" and txt ~= "Tracking" and txt ~= "Not you" then
                                islandPop(1.08)
                        end
                end
        end
        local ptxt = "--"
        local pcol = THEME.TextDim
        if dataPingMs and dataPingMs > 0 then
                ptxt = tostring(math.floor(dataPingMs)) .. "ms"
                if dataPingMs < 80 then pcol = THEME.Good
                elseif dataPingMs < 160 then pcol = THEME.Amber
                else pcol = THEME.Bad end
        end
        hudSet(pingVal, "ping", ptxt)
        hudCol(pingVal, "ping", pcol)
        if ball and root then
                local vel = ballVelocity(ball)
                local speed = vel.Magnitude
                hudSet(speedVal, "speed", tostring(math.floor(speed)))
                hudSet(radiusVal, "radius", tostring(math.floor(parryAccuracy(speed, pingSec))))
        else
                hudSet(speedVal, "speed", "--")
                hudSet(radiusVal, "radius", "--")
        end
        if offsetVal.Parent then
                local offsetMs = math.floor(getParryTimeOffset() * 1000)
                hudSet(offsetVal, "offset", tostring(offsetMs) .. "ms")
                local ocol = offsetMs > 250 and THEME.Bad
                        or (offsetMs > 120 and THEME.Amber or THEME.Text)
                hudCol(offsetVal, "offset", ocol)
        end
        if firesLabel.Parent then
                hudSet(firesLabel, "fires", "fires " .. tostring(totalFires))
        end
        if diagCaption.Parent then
                local tokTxt = hookState.tokenOk and "FOUND" or (hookSupported and "SCANNING" or "NO GETGC")
                local capTxt = (hookState.captured ~= nil) and "ARMED" or "TAP BLOCK ONCE"
                hudSet(diagCaption, "diag", "PRY " .. tokTxt .. " · CAPTURE " .. capTxt)
                hudCol(diagCaption, "diag",
                        (hookState.tokenOk and hookState.captured ~= nil) and THEME.Good or THEME.Amber)
        end
end

-- ============================================================
-- [20] CORE LOOP — server-ball offset parry + 15-stud auto spam
-- ============================================================
local lastHud = 0
renderConn = RunService.RenderStepped:Connect(function()
        pcall(function()
                frameCount = frameCount + 1
                -- v26.7: lockout ping = the WORST case of the two pings.
                -- "Data Ping" can read 0 (first frames after join, or the
                -- stat missing on some executors) — a 0 here collapsed the
                -- anti-double lockout to the 0.14 s fast-ball cooldown and
                -- the double parry returned. GetNetworkPing is always
                -- present, so take whichever reads higher.
                local pingSec = math.max(getPingMs(),
                        getPlayerPingSec() * 1000) / 1000
                local ball = getActiveBall()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                -- per-frame ball physics, computed ONCE (serverBallPos
                -- tracks acceleration — it must run a single time/frame)
                local framePhys = nil

                -- yellow dot = SERVER-side ball, extrapolated by the
                -- parry time offset: 2 x (playerPing + clientPing + machineDelay)
                -- (v26.1: second-order — follows curved flight)
                if ball and root then
                        local zoomies = ball:FindFirstChild("zoomies")
                        if zoomies then
                                local vel = zoomies.VectorVelocity
                                local offset = getParryTimeOffset()
                                local sp, acc2 = serverBallPos(ball, zoomies, offset)
                                framePhys = {
                                        vel = vel, speed = vel.Magnitude,
                                        serverPos = sp, offset = offset,
                                        acc = acc2, -- v26.6: feeds PREDICT extrapolation
                                        -- v26.8: rotation-led curve prediction,
                                        -- sampled from the steering player's yaw
                                        -- ONCE per frame (rotLastRate is set by
                                        -- the call above — constructor fields
                                        -- evaluate in order)
                                        rotAcc = rotCurveAccel(
                                                ball:GetAttribute("target"),
                                                vel.Magnitude),
                                        rotRate = rotLastRate,
                                }
                                serverBallDot.Position = sp
                        else
                                serverBallDot.Position = ball.Position
                                        + ballVelocity(ball) * getParryTimeOffset()
                        end
                        if auraEnabled and not char:FindFirstChild("ByakuganAura") then setupAura() end
                else
                        serverBallDot.Position = Vector3.new(0, -100, 0)
                end

                -- v27.0 NEURA: observe/train the fired approach
                neuraObserve(ball, root, framePhys)

                -- ===== AUTO SPAM (v26.9 — proximity-only) =====
                -- v26.9: engages on PURE PROXIMITY — the ball close to
                -- US, regardless of who it is targeting (the target
                -- attribute flickers nil mid-flight and a gate on it
                -- let close balls through unspammed). Still capped per
                -- engagement + release-gated — an infinite spam on a
                -- hovering ball was redirecting it into us and getting
                -- us killed (v26.3 lesson kept).
                -- v27.2: engage 10 -> 13 studs, release 14 -> 16
                -- (hysteresis kept).
                -- v27.3 VERTICAL BAND: spam no longer fires blindly —
                -- if the ball is curved OVER our head or UNDER our
                -- feet (outside +-3.1 studs of root Y = our character
                -- height), spam HOLDS (no fires) and the sphere parry
                -- takes the shot; the moment the ball is back in
                -- band, spam resumes. The hold also clears the
                -- once-per-approach arm so the sphere can fire
                -- immediately.
                if autoSpamEnabled and ball and root
                        and not deathActive and not infActive then
                        local distUs = (root.Position - ball.Position).Magnitude
                        local protected = root:FindFirstChild("SingularityCape") ~= nil
                                or ball:FindFirstChild("ComboCounter") ~= nil
                        local inBand = math.abs(
                                ball.Position.Y - root.Position.Y) <= 3.1
                        spamHold = spamActive and not inBand
                        if spamHold then
                                -- hand the approach to the sphere parry
                                lastFireInfo = nil
                        end
                        if not spamActive then
                                if os.clock() >= spamCooldownUntil
                                        and distUs <= 13 and not protected then
                                        spamActive = true
                                        spamFires = 0
                                        pushStatus("SPAM ENGAGED", 1.4)
                                        islandPop(1.25)
                                        fxBurst()
                                end
                        elseif distUs > 16 or protected then
                                spamActive = false
                                spamHold = false
                                spamCooldownUntil = os.clock() + 0.6
                                pushStatus("Spam released", 0.8)
                        end
                elseif spamActive then
                        spamActive = false
                        spamHold = false
                        spamCooldownUntil = os.clock() + 0.6
                else
                        spamHold = false
                end
                -- fires: 0.03 s throttle (~33/s) + cap 30 per engagement
                -- (v27.2) — v27.3: never while the ball is outside the
                -- vertical band (spamHold)
                if spamActive and not spamHold and spamFires < 30
                        and os.clock() - lastSpamAt >= 0.03
                        and os.clock() - lastAutoFireAt >= 0.03 then
                        lastSpamAt = os.clock()
                        lastAutoFireAt = os.clock()
                        -- v26.7: spam shots also arm the anti-double gate,
                        -- so the sphere branch cannot stack a wasted packet
                        -- on top of an engagement that is already firing
                        lastFireInfo = { ball = ball, t = os.clock(),
                                vel = ballVelocity(ball),
                                target = ball:GetAttribute("target") }
                        if fireParryRemote(getCurveCFrame()) then
                                spamFireCount = spamFireCount + 1
                                spamFires = spamFires + 1
                                if spamFires >= 30 then
                                        spamActive = false
                                        spamCooldownUntil = os.clock() + 1
                                end
                        end
                end

                -- ===== AUTO PARRY (TTI interception + server-ball offset) =====
                if isRunning then
                        if ball and root then
                                local zoomies = ball:FindFirstChild("zoomies")
                                if zoomies then
                                        local target = ball:GetAttribute("target")
                                        -- v26.3: reset parry state ONLY on a real
                                        -- target change — nil-flicker must not
                                        -- re-arm the parry (burst-fire bug)
                                        if target ~= nil
                                                and lastTargetOf[ball] ~= target then
                                                lastTargetOf[ball] = target
                                                parriedUntil = 0
                                                lastTtiBucket = -1
                                                -- v27.1: a target change ENDS the
                                                -- approach — the once-per-approach
                                                -- gate re-arms for the next exchange
                                                lastFireInfo = nil
                                        end
                                        local speed, serverPos
                                        if framePhys then
                                                speed = framePhys.speed
                                                serverPos = framePhys.serverPos
                                        else
                                                speed = zoomies.VectorVelocity.Magnitude
                                                serverPos = ball.Position
                                                        + zoomies.VectorVelocity * getParryTimeOffset()
                                        end
                                        local vel = framePhys and framePhys.vel
                                                or zoomies.VectorVelocity
                                        local distServer = (serverPos - root.Position).Magnitude
                                        local distReal = (root.Position - ball.Position).Magnitude
                                        local accuracy = parryAccuracy(speed, pingSec)

                                        -- PATH / TTI MATH — closest point of the ball's
                                        -- flight path to us. v26.4: measured from the REAL
                                        -- ball, NOT the offset-extrapolated phantom. The
                                        -- phantom sat up to ~200 studs ahead of reality,
                                        -- so tti read `offset` seconds small and the fire
                                        -- window added the same offset AGAIN — cross-map
                                        -- spam + early parries. Distance-independent:
                                        -- a 700 stud/s ball from 500 studs still triggers
                                        -- on TIME, not on a radius it crosses in a frame.
                                        -- v26.6 PREDICT: optional future-ball
                                        -- measurement. Lead = PREDICT% x parry
                                        -- offset, second-order (same curve
                                        -- model as the yellow dot). It lives
                                        -- ONLY on the measurement side — the
                                        -- fire window stays the pure v26.4
                                        -- send lead, so leads never stack.
                                        local measPos = ball.Position
                                        if predictPct > 0 then
                                                local lead = predictPct
                                                        * getParryTimeOffset()
                                                if framePhys then
                                                        -- v26.8: measured acc +
                                                        -- rotation-led steering acc —
                                                        -- the steerer's yaw moves
                                                        -- before the ball's own
                                                        -- motion shows the curve,
                                                        -- so the prediction leads
                                                        -- instead of trails it
                                                        measPos = ball.Position
                                                                + vel * lead
                                                                + (framePhys.acc
                                                                        + framePhys.rotAcc)
                                                                        * (lead * lead * 0.5)
                                                else
                                                        measPos = ball.Position
                                                                + vel * lead
                                                end
                                        end
                                        local tti, lateral = math.huge, math.huge
                                        if speed > 1 then
                                                local dir = vel.Unit
                                                local rel = root.Position - measPos
                                                local along = rel:Dot(dir)
                                                if along > 0 then
                                                        tti = along / speed
                                                        lateral = (rel - dir * along).Magnitude
                                                end
                                        end
                                        -- v27.3 SPHERE TRIGGER (user spec) — a
                                        -- uniform sphere around us; fire when
                                        -- the ball's flight path passes inside
                                        -- it. Radius: base 15, sqrt(velocity)
                                        -- growth, ping+delay compensated (the
                                        -- delay converted to studs at the
                                        -- ball's own speed), clamped 15..50:
                                        --   R = (15 + sqrt(speed)
                                        --        + speed*(2*ping + 0.06)) / 2
                                        local sphereR = math.clamp((15
                                                + math.sqrt(speed)
                                                + speed * (pingSec * 2 + 0.06))
                                                / 2, 15, 50)
                                        -- touch lead: SPHERE mode = the sphere's
                                        -- own crossing time (R/speed), floored
                                        -- at the packet's send lead (2*ping +
                                        -- 0.1 — a fast ball must be fired BEFORE
                                        -- touch or the packet lands after
                                        -- contact), capped 0.5 s. TIMER mode =
                                        -- the classic v26.4/v27.2 send-lead
                                        -- window, verbatim. NEURA's learned
                                        -- latency bias still shifts either one.
                                        local sphereT = (parryMode == "Sphere"
                                                and math.min(math.max(
                                                        sphereR / math.max(speed, 1),
                                                        pingSec * 2 + 0.1), 0.5)
                                                or ttiFireWindow(speed))
                                                + neuraBias(root, ball,
                                                        framePhys, vel,
                                                        speed, tti, lateral,
                                                        pingSec)
                                        -- kept for the "Getting close" status
                                        -- (+ TIMER mode's proximity fallback)
                                        local nearDist = predictPct > 0
                                                and (root.Position - measPos).Magnitude
                                                or distReal
                                        -- frame-rate independent touch: the
                                        -- path must pass INSIDE the sphere
                                        -- (lateral) and reach it within the
                                        -- lead (tti) — identical result to a
                                        -- continuous touch test, but mobile
                                        -- frame drops can never tunnel past
                                        -- the sphere between two frames.
                                        -- TIMER mode keeps the EXACT v26.4/
                                        -- v27.2 trigger: tti <= window inside
                                        -- the accuracy radius, plus the real-
                                        -- distance proximity fallback.
                                        local sphereHit
                                        if parryMode == "Sphere" then
                                                sphereHit = tti <= sphereT
                                                        and lateral <= sphereR
                                        else
                                                sphereHit = (tti <= sphereT
                                                        and lateral <= math.max(
                                                                accuracy * 0.55, 12))
                                                        or (nearDist <= accuracy
                                                                and (speed < 140
                                                                        or nearDist < 70))
                                        end
                                        -- v27.4: the sphere is VISIBLE in SPHERE
                                        -- mode — a red ForceField bubble hugging
                                        -- the live hitbox, resized every frame
                                        if parryMode == "Sphere" then
                                                sphereVisShow(root, sphereR)
                                        end
                                        -- v27.2: PANIC refire REMOVED. On a fast
                                        -- curve the redirect can flip in steps the
                                        -- dot < 0.3 latch reads as steering, the
                                        -- lockout expired while the ball still read
                                        -- incoming, and PANIC — whose trigger
                                        -- (tti <= half window, lateral <= 1.5x
                                        -- radius) is EXACTLY a fast curve's
                                        -- signature — fired the second packet.
                                        -- With it gone the sphere branch is the only
                                        -- auto fire that can ever touch a targeted
                                        -- approach: exactly ONE packet.
                                        local blocked = deathActive or infActive
                                                or ball:FindFirstChild("ComboCounter") ~= nil
                                                or root:FindFirstChild("SingularityCape") ~= nil
                                        -- v27.3: isBallTargetting() gate — the
                                        -- sphere fires ONLY on a ball locked on
                                        -- us (deflection/knockback pinballs
                                        -- grazing the sphere never double-fire)
                                        local armed = os.clock() >= parriedUntil
                                                and isBallTargetting(ball)
                                                and not blocked

                                        -- v26.7 ANTI-DOUBLE-PARRY: after an auto fire
                                        -- the ball state is STALE for ~2 x ping (the
                                        -- redirect hasn't replicated), so the TTI
                                        -- branch must not fire twice on one approach.
                                        -- v27.1 REWRITE: the old 6-stud/s
                                        -- velocity release was the double's hiding
                                        -- spot — a homing ball bends its velocity
                                        -- > 6 studs/s within ~0.1 s, the gate
                                        -- dissolved, and after the lockout the TTI
                                        -- branch re-fired on the SAME approach.
                                        -- An approach is now closed ONLY by a
                                        -- target change, a new ball, or the 1.2 s
                                        -- failsafe. v27.2: PANIC (the last branch
                                        -- that could refire an approach) is REMOVED
                                        -- — this gate is now structurally complete:
                                        -- exactly ONE packet per targeted approach
                                        local sameApproach = lastFireInfo ~= nil
                                                and lastFireInfo.ball == ball
                                                and target == lastFireInfo.target
                                                and os.clock() - lastFireInfo.t <= 1.2

                                        if armed and sphereHit
                                                and not sameApproach
                                                -- v26.8: the curve veto relaxes only when
                                                -- the ROTATION predictor is leading the
                                                -- bend (PREDICT on + opponent yaw rate
                                                -- >= 1 rad/s) — the predicted path already
                                                -- accounts for the curve, so a curved ball
                                                -- can be parried ON TIME instead of
                                                -- a late fire. Without PREDICT the veto
                                                -- behaves exactly as before
                                                and (not isCurved(ball, pingSec)
                                                        or (rotCurveOn
                                                                and predictPct > 0
                                                                and target ~= LocalPlayer.Name
                                                                and framePhys ~= nil
                                                                and framePhys.rotRate >= 1.0))
                                                and os.clock() - lastAutoFireAt >= 0.08 then
                                                lastAutoFireAt = os.clock()
                                                -- lockout covers the redirect window:
                                                -- max(speed cooldown, 2 x ping + 0.06)
                                                parriedUntil = os.clock()
                                                        + math.max(parryCooldown(speed),
                                                                pingSec * 2 + 0.06)
                                                lastFireInfo = { ball = ball, t = os.clock(),
                                                        vel = vel, target = target,
                                                        nn = neuraPending }
                                                lastTtiBucket = -1
                                                fxBurst()
                                                fireSelected()
                                                setBaseStatus(parryMode == "Sphere"
                                                        and "SPHERE PARRY"
                                                        or (predictPct > 0
                                                                and "PREDICT PARRY"
                                                                or "TTI PARRY"))
                                        elseif target == LocalPlayer.Name then
                                                if blocked then
                                                        setBaseStatus("PROTECTED")
                                                elseif tti < math.huge and tti <= sphereT + 0.6 then
                                                        -- quantized to 0.1 s steps: no string
                                                        -- garbage every frame (mobile GC lag)
                                                        local bucket = math.floor(tti * 10)
                                                        if bucket ~= lastTtiBucket then
                                                                lastTtiBucket = bucket
                                                                setBaseStatus(string.format("TTI %.1f", bucket / 10))
                                                        end
                                                elseif nearDist <= accuracy + 14 then
                                                        setBaseStatus("Getting close")
                                                else
                                                        setBaseStatus("Tracking")
                                                end
                                        else
                                                setBaseStatus("Not you")
                                        end
                                else
                                        setBaseStatus("No zoomies")
                                end
                        else
                                setBaseStatus(getBalls() and "Waiting" or "No ball")
                        end
                end

                -- v27.4: the visible sphere only lives while it IS the
                -- trigger (sphere mode + auto parry + live zoomies ball)
                if parryMode ~= "Sphere" or not isRunning
                        or not (ball and root)
                        or not ball:FindFirstChild("zoomies") then
                        sphereVisHide()
                end

                if os.clock() - lastHud >= (perfMode and 0.34 or 0.2) then
                        lastHud = os.clock()
                        updateHUD(ball, root, pingSec)
                end
        end)
end)

end, function(err)
        byakFatal(err)
end)
