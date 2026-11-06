-- ============================================================
-- Blade Ball Mobile — BYAKUGAN RS26  (Audi RS × iOS 26 Fluid)
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
-- PARRY MATH (new):
--        parry_time_offset = 2 x (playerPing + clientPing
--                                    + machineDelay)
--        applied to extrapolate the SERVER-side ball position:
--        serverBallPos = ballPos + ballVel * offset
--        Trigger fires when the server ball (or the real ball)
--        enters the NAZK parry-accuracy radius.
-- AUTO SPAM (new):
--        distance(ball -> its target) <= 15 studs  ->  spam
--        ENGAGES (rapid hook-replay fires) and releases above
--        22 studs (hysteresis, no flicker).
-- Boot-safety: UI builds FIRST, no infinite waits, every error
--        shows a visible red panel instead of silent death.
-- ============================================================

local function byakFatal(msg)
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

-- ============================================================
-- [2] STATE
-- ============================================================
local isRunning        = true         -- auto parry ON at boot
local dotEnabled       = true
local auraEnabled      = true
local autoSpamEnabled  = true         -- NEW: 15-stud auto spam
local fxEnabled        = true         -- parry shockwave FX
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
local spamActive     = false         -- NEW: auto-spam engaged state
local parriedUntil   = 0
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

local function findTokenFunction()
        if hookState.tokenOk then return true end
        if not get_gc then return false end
        local found
        pcall(function()
                for _, obj in get_gc(true) do
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
        if os.clock() - curveProps.lastWarping < reachTime / 1.4 then return true end
        if os.clock() - curveProps.curving < reachTime / 1.1 then return true end
        return dot < dotThreshold
end

-- NAZK parry-accuracy radius: ping + speed derived
local function parryAccuracy(speed, pingSec)
        local pingThreshold = math.clamp(pingSec * 10, 5, 17)
        local capped = math.min(math.max(speed - 9.5, 0), 650)
        local divisor = 2.4 + capped * 0.002
        return pingThreshold + math.max(speed / divisor, 9.5)
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
        Carbon    = Color3.fromRGB(13, 13, 16),
        Panel     = Color3.fromRGB(27, 27, 32),
        PanelDark = Color3.fromRGB(18, 18, 22),
        Hover     = Color3.fromRGB(36, 36, 43),
        Stroke    = Color3.fromRGB(48, 48, 56),
        Text      = Color3.fromRGB(238, 238, 240),
        TextDim   = Color3.fromRGB(128, 128, 136),
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
                        Size = e.Size, Position = e.Pos, BackgroundColor3 = THEME.RedGlow,
                        BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = fxGroup,
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
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 1,
        Visible = false,
        Parent = screenGui,
})
corner(main, 20)
stroke(main, THEME.RedGlow, 4, 0.86)
local mainStroke = stroke(main, THEME.Red, 1.4, 0.15)
local strokeGradient = create("UIGradient", {
        Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, THEME.Red),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(64, 64, 74)),
                ColorSequenceKeypoint.new(1, THEME.Red),
        }),
        Parent = mainStroke,
})
tw(strokeGradient, 4, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1):Play()
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
tw(ambientGrad, 16, { Rotation = 395 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1):Play()

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
        Text = "iOS 26 FLUID • HOOK REPLAY EDITION",
        Font = Enum.Font.GothamBold, TextSize = 9,
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
                sweep.Position = UDim2.new(0, -90, 0, 0)
                local t = tw(sweep, 1.1, { Position = UDim2.new(1, 20, 0, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                t:Play()
                local done = false
                t.Completed:Connect(function() done = true end)
                while not done and uiAlive and sweep.Parent do task.wait(0.1) end
                task.wait(6)
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

-- ============================================================
-- [12] ROW BUILDERS — spring toggles + fluid steppers
-- ============================================================
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
        return row
end

-- ============================================================
-- [13] DYNAMIC ISLAND — the pill (kept from the approved UI)
-- ============================================================
local pill = create("CanvasGroup", {
        Name = "Island", AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(96, 34),
        BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 0.12,
        BorderSizePixel = 0, ClipsDescendants = true, GroupTransparency = 1,
        Visible = false, Parent = screenGui,
})
fullCorner(pill)
stroke(pill, THEME.Glass, 1, 0.82)
sheen(pill, 10, 17)
local pillScale = create("UIScale", { Scale = 1, Parent = pill })
local pillDot = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 14, 0.5, 0),
        BackgroundColor3 = THEME.TextDim, BorderSizePixel = 0, Parent = pill,
})
fullCorner(pillDot)
local pillLabel = create("TextLabel", {
        Size = UDim2.new(1, -44, 1, 0), Position = UDim2.new(0, 30, 0, 0),
        BackgroundTransparency = 1, Text = "Idle",
        Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = pill,
})
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
local pillRingStroke = stroke(pillRing, THEME.RedGlow, 2.5, 1)

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

-- THE SHOCKWAVE — edge glow + island ring on every engaged parry
fxBurst = function()
        if not fxEnabled then return end
        if fxGroup and fxGroup.Parent then
                fxGroup.GroupTransparency = 0.12
                tw(fxGroup, 0.34, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
        end
        if pillRing and pillRing.Parent then
                pillRing.Size = UDim2.fromOffset(34, 34)
                pillRingStroke.Transparency = 0.15
                tw(pillRing, 0.55, { Size = UDim2.fromOffset(130, 130) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
                tw(pillRingStroke, 0.55, { Transparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out):Play()
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
-- [16] WIRE ROWS TO THE ENGINE
-- ============================================================
makeSwitchRow("AUTO PARRY", isRunning, function(v)
        isRunning = v
        setStatus(v)
        pushStatus(v and "Parry on" or "Parry off", 1)
end)

makeSwitchRow("AUTO SPAM <15", autoSpamEnabled, function(v)
        autoSpamEnabled = v
        if not v then spamActive = false end
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
        pcall(function() screenGui:Destroy() end)
        pcall(function() serverBallDot:Destroy() end)
        local char = LocalPlayer.Character
        local hl = char and char:FindFirstChild("ByakuganAura")
        if hl then hl:Destroy() end
end

-- ============================================================
-- [18] BOOT SEQUENCE — springs all the way in
-- ============================================================
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
        pill.Visible = true
        pill.GroupTransparency = 1
        tw(pill, 0.3, { GroupTransparency = 0 }):Play()
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
        if pingVal.Parent then
                pingVal.Text = ptxt
                pingVal.TextColor3 = pcol
        end
        if ball and root then
                local vel = ballVelocity(ball)
                local speed = vel.Magnitude
                if speedVal.Parent then speedVal.Text = tostring(math.floor(speed)) end
                if radiusVal.Parent then radiusVal.Text = tostring(math.floor(parryAccuracy(speed, pingSec))) end
        else
                if speedVal.Parent then speedVal.Text = "--" end
                if radiusVal.Parent then radiusVal.Text = "--" end
        end
        if offsetVal.Parent then
                local offsetMs = math.floor(getParryTimeOffset() * 1000)
                offsetVal.Text = tostring(offsetMs) .. "ms"
                offsetVal.TextColor3 = offsetMs > 250 and THEME.Bad
                        or (offsetMs > 120 and THEME.Amber or THEME.Text)
        end
        if firesLabel.Parent then
                firesLabel.Text = "fires " .. tostring(totalFires)
        end
        if diagCaption.Parent then
                local tokTxt = hookState.tokenOk and "FOUND" or (hookSupported and "SCANNING" or "NO GETGC")
                local capTxt = (hookState.captured ~= nil) and "ARMED" or "TAP BLOCK ONCE"
                diagCaption.Text = "PRY " .. tokTxt .. " · CAPTURE " .. capTxt
                diagCaption.TextColor3 = (hookState.tokenOk and hookState.captured ~= nil) and THEME.Good or THEME.Amber
        end
end

-- ============================================================
-- [20] CORE LOOP — server-ball offset parry + 15-stud auto spam
-- ============================================================
local lastHud = 0
renderConn = RunService.RenderStepped:Connect(function()
        pcall(function()
                frameCount = frameCount + 1
                local pingSec = getPingMs() / 1000
                local ball = getActiveBall()
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")

                -- yellow dot = SERVER-side ball, extrapolated by the
                -- parry time offset: 2 x (playerPing + clientPing + machineDelay)
                if ball and root then
                        local vel = ballVelocity(ball)
                        serverBallDot.Position = ball.Position + vel * getParryTimeOffset()
                        if auraEnabled and not char:FindFirstChild("ByakuganAura") then setupAura() end
                else
                        serverBallDot.Position = Vector3.new(0, -100, 0)
                end

                -- ===== AUTO SPAM =====
                -- distance from the ball to ITS target <= 15 studs -> ENGAGE
                -- (rapid hook-replay fires); releases above 22 studs.
                if autoSpamEnabled and ball then
                        local _, tRoot = ballTargetPlayer(ball)
                        if tRoot then
                                local targetDist = (tRoot.Position - ball.Position).Magnitude
                                if targetDist <= 15 and not spamActive then
                                        spamActive = true
                                        pushStatus("SPAM ENGAGED", 1.4)
                                        islandPop(1.25)
                                        fxBurst()
                                elseif targetDist > 22 and spamActive then
                                        spamActive = false
                                        pushStatus("Spam released", 0.8)
                                end
                        end
                elseif spamActive then
                        spamActive = false
                end
                if spamActive and os.clock() - lastSpamAt >= 0.015 then
                        lastSpamAt = os.clock()
                        if fireParryRemote(getCurveCFrame()) then
                                spamFireCount = spamFireCount + 1
                        end
                end

                -- ===== AUTO PARRY (NAZK trigger + server-ball offset) =====
                if isRunning then
                        if ball and root then
                                local zoomies = ball:FindFirstChild("zoomies")
                                if zoomies then
                                        local target = ball:GetAttribute("target")
                                        if lastTargetOf[ball] ~= target then
                                                lastTargetOf[ball] = target
                                                parriedUntil = 0
                                        end
                                        local speed = zoomies.VectorVelocity.Magnitude
                                        local serverPos = ball.Position
                                                + zoomies.VectorVelocity * getParryTimeOffset()
                                        local distServer = (serverPos - root.Position).Magnitude
                                        local distReal = (root.Position - ball.Position).Magnitude
                                        local accuracy = parryAccuracy(speed, pingSec)
                                        if os.clock() >= parriedUntil
                                                and target == LocalPlayer.Name
                                                and not isCurved(ball, pingSec)
                                                and ball:FindFirstChild("ComboCounter") == nil
                                                and root:FindFirstChild("SingularityCape") == nil
                                                and not deathActive and not infActive
                                                and (distServer <= accuracy or distReal <= accuracy) then
                                                parriedUntil = os.clock() + 1
                                                fxBurst()
                                                fireSelected()
                                        elseif target == LocalPlayer.Name then
                                                if math.min(distServer, distReal) <= accuracy + 14 then
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

                if os.clock() - lastHud >= 0.12 then
                        lastHud = os.clock()
                        updateHUD(ball, root, pingSec)
                end
        end)
end)

end, function(err)
        byakFatal(err)
end)
