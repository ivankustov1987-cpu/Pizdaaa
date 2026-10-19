-- ollie // harbor havoc v6
-- fix: Network.Events binary fire (Cobalt dump), mouse/camera silent, aim toggle

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

local IS_MOBILE = UserInput.TouchEnabled

local S = {
    Silent       = true,
    SilentFOV    = IS_MOBILE and 240 or 200,
    SilentPart   = "Head",
    SilentTeam   = true,
    SilentWall   = false,

    Predict      = true,
    BulletSpeed  = 300,

    Aimbot       = false, -- toggle: on until off
    AimbotFOV    = IS_MOBILE and 240 or 200,
    AimbotSmooth = IS_MOBILE and 0.28 or 0.18,
    AimbotPart   = "Head",
    AimbotTeam   = true,
    AimbotWall   = false,

    ESP          = true,
    ESPBox       = true,
    ESPName      = true,
    ESPHealth    = true,
    ESPDistance  = true,
    ESPTracer    = false,
    ESPTeam      = true,
    ESPMaxDist   = 2000,
}

-- ── current silent target (shared) ────────────────────────────────────────────
local currentTargetPos = nil -- Vector3 or nil

-- ── velocity ──────────────────────────────────────────────────────────────────
local velMap, prevMap = {}, {}

local function track(key, root, dt)
    if not root then velMap[key] = Vector3.zero; prevMap[key] = nil; return end
    velMap[key]  = prevMap[key] and ((root.Position - prevMap[key]) / dt) or Vector3.zero
    prevMap[key] = root.Position
end

RunService.Heartbeat:Connect(function(dt)
    if dt <= 0 then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p \~= LP then
            local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            track(p, r, dt)
        end
    end
    local folder = workspace:FindFirstChild("Folder")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            local r = m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)
            if r then track(m, r, dt) end
        end
    end
end)

-- ── targets ───────────────────────────────────────────────────────────────────
local function getTargets()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end
        table.insert(list, {
            root = root, vel = velMap[p] or Vector3.zero,
            name = p.DisplayName, hum = hum, team = p.Team, p = p,
            model = char,
        })
    end
    local folder = workspace:FindFirstChild("Folder")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if not model:IsA("Model") then continue end
            local skip = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == model then skip = true; break end
            end
            if skip then continue end
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                or model:FindFirstChildWhichIsA("BasePart")
            if not root or (root:IsA("BasePart") and root.Size.Magnitude < 4) then continue end
            table.insert(list, {
                root = root, vel = velMap[model] or Vector3.zero,
                name = model.Name, hum = model:FindFirstChildOfClass("Humanoid"),
                team = nil, p = nil, model = model,
            })
        end
    end
    return list
end

local function partPos(t, partName)
    if t.p and t.p.Character then
        local part = t.p.Character:FindFirstChild(partName)
        if part then return part.Position end
    end
    return t.root.Position
end

local function predictedPos(t, partName)
    local base = partPos(t, partName)
    if not S.Predict then return base end
    local dist = (base - Camera.CFrame.Position).Magnitude
    return base + t.vel * (dist / math.max(S.BulletSpeed, 1))
end

local function sameTeam(t)
    return t.team and LP.Team and t.team == LP.Team
end

local function wallClear(pos, targetModel)
    local filter = {}
    if LP.Character then table.insert(filter, LP.Character) end
    if targetModel then table.insert(filter, targetModel) end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = filter
    params.FilterType = Enum.RaycastFilterType.Exclude
    local origin = Camera.CFrame.Position
    return workspace:Raycast(origin, pos - origin, params) == nil
end

local function getBest(fov, part, teamCheck, doWall)
    local best, bestD = nil, fov
    local vs = Camera.ViewportSize
    local cx, cy = vs.X * 0.5, vs.Y * 0.5
    for _, t in ipairs(getTargets()) do
        if teamCheck and sameTeam(t) then continue end
        local pos = predictedPos(t, part)
        if doWall and not wallClear(pos, t.model) then continue end
        local sp, vis = Camera:WorldToViewportPoint(pos)
        if not vis or sp.Z < 0 then continue end
        local d = math.sqrt((sp.X - cx)^2 + (sp.Y - cy)^2)
        if d < bestD then bestD = d; best = t end
    end
    return best
end

local function refreshSilentTarget()
    if not S.Silent then currentTargetPos = nil; return end
    local t = getBest(S.SilentFOV, S.SilentPart, S.SilentTeam, S.SilentWall)
    currentTargetPos = t and predictedPos(t, S.SilentPart) or nil
end

RunService.RenderStepped:Connect(refreshSilentTarget)

-- ── mouse / camera spoof (silent that works with binary Network events) ───────
-- ClientCore packs aim from mouse/camera; spoof Hit before FireServer
local mouse = LP:GetMouse()

local function spoofedHit()
    if S.Silent and currentTargetPos then
        return CFrame.new(currentTargetPos)
    end
    return mouse.Hit
end

local function spoofedUnitRay()
    local origin = Camera.CFrame.Position
    if S.Silent and currentTargetPos then
        local dir = (currentTargetPos - origin).Unit
        return Ray.new(origin, dir * 10000)
    end
    return mouse.UnitRay
end

-- property hooks on mouse
pcall(function()
    local mt = getrawmetatable(mouse)
    if not mt then return end
    setreadonly(mt, false)
    local oldIndex = mt.__index
    mt.__index = newcclosure(function(self, key)
        if S.Silent and currentTargetPos then
            if key == "Hit" then return spoofedHit() end
            if key == "UnitRay" then return spoofedUnitRay() end
            if key == "Target" then
                local t = getBest(S.SilentFOV, S.SilentPart, S.SilentTeam, S.SilentWall)
                if t and t.p and t.p.Character then
                    return t.p.Character:FindFirstChild(S.SilentPart) or t.root
                end
            end
        end
        return oldIndex(self, key)
    end)
    setreadonly(mt, true)
    print("ollie: mouse Hit/UnitRay hooked")
end)

-- also hook Mouse.Hit via __namecall GetPropertyChangedSignal path — skip

-- Network.Events FireServer log + optional camera snap at fire frame
local function getNetworkEvents()
    local net = RS:FindFirstChild("Network")
    if not net then return nil end
    return net:FindFirstChild("Events")
end

local hookedRemotes = {}

local function hookRemote(remote)
    if not remote or hookedRemotes[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return end
    hookedRemotes[remote] = true
end

local function hookAllNetwork()
    local events = getNetworkEvents()
    if not events then
        warn("ollie: Network.Events not found yet")
        return false
    end
    for _, ch in ipairs(events:GetChildren()) do
        hookRemote(ch)
    end
    events.ChildAdded:Connect(hookRemote)
    print("ollie: Network.Events tracked", #events:GetChildren())
    return true
end

-- namecall: on any Network FireServer, force camera look at target this frame
pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local oldNC = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and S.Silent and currentTargetPos then
            local ok = false
            pcall(function()
                local par = self.Parent
                if par and par.Name == "Events" then
                    local gp = par.Parent
                    if gp and gp.Name == "Network" then ok = true end
                end
            end)
            if ok then
                -- snap camera to target so ClientCore serializes correct aim if it reads camera
                local camPos = Camera.CFrame.Position
                Camera.CFrame = CFrame.new(camPos, currentTargetPos)
            end
        end
        return oldNC(self, ...)
    end)
    setreadonly(mt, true)
    print("ollie: Network FireServer camera-snap hooked")
end)

task.spawn(function()
    for _ = 1, 30 do
        if hookAllNetwork() then break end
        task.wait(1)
    end
end)

-- ── aimbot toggle (always on while enabled) ───────────────────────────────────
RunService.RenderStepped:Connect(function()
    if not S.Aimbot then return end
    local t = getBest(S.AimbotFOV, S.AimbotPart, S.AimbotTeam, S.AimbotWall)
    if not t then return end
    local pos = predictedPos(t, S.AimbotPart)
    local goal = CFrame.new(Camera.CFrame.Position, pos)
    Camera.CFrame = Camera.CFrame:Lerp(goal, S.AimbotSmooth)
end)

-- ── ESP ───────────────────────────────────────────────────────────────────────
local HAS_DRAWING = pcall(function()
    local d = Drawing.new("Square"); d:Remove()
end)

local espCache = {}

local function clearESP(key)
    if not espCache[key] then return end
    for _, v in pairs(espCache[key]) do pcall(function() v:Remove() end) end
    espCache[key] = nil
end

local function initESP(key)
    if not HAS_DRAWING then return end
    clearESP(key)
    local function D(t, props)
        local d = Drawing.new(t)
        for k, v in pairs(props) do d[k] = v end
        return d
    end
    espCache[key] = {
        box  = D("Square", {Filled=false, Color=Color3.fromRGB(255,50,50), Thickness=1, Visible=false}),
        name = D("Text", {Center=true, Color=Color3.fromRGB(255,255,255), Size=13, Outline=true, Visible=false}),
        hbBg = D("Square", {Filled=true, Color=Color3.fromRGB(0,0,0), Visible=false}),
        hb   = D("Square", {Filled=true, Color=Color3.fromRGB(60,220,60), Visible=false}),
        dist = D("Text", {Center=true, Color=Color3.fromRGB(200,200,200), Size=11, Outline=true, Visible=false}),
        tracer = D("Line", {Thickness=1, Color=Color3.fromRGB(255,50,50), Visible=false}),
    }
end

local function getScreenBBox(root, char)
    local parts = {}
    if char then
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") then table.insert(parts, v) end
        end
    end
    if #parts == 0 then table.insert(parts, root) end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for _, part in ipairs(parts) do
        local sp, vis = Camera:WorldToViewportPoint(part.Position)
        if vis then
            any = true
            minX = math.min(minX, sp.X); minY = math.min(minY, sp.Y)
            maxX = math.max(maxX, sp.X); maxY = math.max(maxY, sp.Y)
        end
    end
    if not any then return nil end
    local w = math.clamp(maxX - minX, 10, Camera.ViewportSize.X * 0.8)
    local h = math.clamp(maxY - minY, 10, Camera.ViewportSize.Y * 0.8)
    return minX, minY, w, h
end

if HAS_DRAWING then
    RunService.RenderStepped:Connect(function()
        local alive = {}
        for _, t in ipairs(getTargets()) do
            alive[t.p or t.model or t.root] = t
        end
        for key in pairs(espCache) do
            if not alive[key] then clearESP(key) end
        end
        for key, t in pairs(alive) do
            if not espCache[key] then initESP(key) end
            local e = espCache[key]
            if not e then continue end
            local dist3d = (t.root.Position - Camera.CFrame.Position).Magnitude
            local show = S.ESP and not (S.ESPTeam and sameTeam(t))
                and dist3d <= S.ESPMaxDist and (not t.hum or t.hum.Health > 0)
            if not show then
                for _, v in pairs(e) do v.Visible = false end
                continue
            end
            local rsp, rvis = Camera:WorldToViewportPoint(t.root.Position)
            if not rvis then
                for _, v in pairs(e) do v.Visible = false end
                continue
            end
            local bx, by, bw, bh = getScreenBBox(t.root, t.model)
            if not bx then
                for _, v in pairs(e) do v.Visible = false end
                continue
            end
            e.box.Visible = S.ESPBox
            e.box.Position = Vector2.new(bx, by)
            e.box.Size = Vector2.new(bw, bh)
            e.name.Visible = S.ESPName
            e.name.Position = Vector2.new(bx + bw/2, by - 15)
            e.name.Text = t.name
            if t.hum and t.hum.MaxHealth > 0 then
                local hp = math.clamp(t.hum.Health / t.hum.MaxHealth, 0, 1)
                e.hbBg.Visible = S.ESPHealth
                e.hbBg.Position = Vector2.new(bx - 6, by)
                e.hbBg.Size = Vector2.new(3, bh)
                e.hb.Visible = S.ESPHealth
                e.hb.Position = Vector2.new(bx - 6, by + bh * (1 - hp))
                e.hb.Size = Vector2.new(3, bh * hp)
                e.hb.Color = Color3.fromRGB((1 - hp) * 255, hp * 255, 0)
            else
                e.hbBg.Visible = false; e.hb.Visible = false
            end
            e.dist.Visible = S.ESPDistance
            e.dist.Position = Vector2.new(bx + bw/2, by + bh + 2)
            e.dist.Text = math.floor(dist3d) .. "u"
            e.tracer.Visible = S.ESPTracer
            e.tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
            e.tracer.To = Vector2.new(rsp.X, rsp.Y)
        end
    end)
else
    warn("ollie: Drawing API missing — ESP off")
    S.ESP = false
end

Players.PlayerRemoving:Connect(function(p)
    clearESP(p); velMap[p] = nil; prevMap[p] = nil
end)

-- ── mobile HUD ────────────────────────────────────────────────────────────────
local function mobileHUD()
    local pg = LP:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "ollie_v6"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = pg

    local function mk(text, y, on, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(112, 42)
        b.Position = UDim2.new(1, -122, 0, y)
        b.BackgroundTransparency = 0.2
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        b.Text = text
        b.Parent = gui
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        local function paint(state)
            b.BackgroundColor3 = state and Color3.fromRGB(30, 140, 60) or Color3.fromRGB(50, 50, 50)
        end
        paint(on)
        b.MouseButton1Click:Connect(function()
            local st = cb()
            paint(st)
            b.Text = text:gsub(":.*", "") .. (st and ": ON" or ": OFF")
        end)
        return b
    end

    mk("AIM: OFF", 90, false, function()
        S.Aimbot = not S.Aimbot
        return S.Aimbot
    end)
    mk("SIL: ON", 140, true, function()
        S.Silent = not S.Silent
        return S.Silent
    end)
    mk("PRED: ON", 190, true, function()
        S.Predict = not S.Predict
        return S.Predict
    end)
    mk("ESP: ON", 240, true, function()
        S.ESP = not S.ESP
        return S.ESP
    end)
end

if IS_MOBILE then pcall(mobileHUD) end

-- ── Rayfield ──────────────────────────────────────────────────────────────────
local Rayfield
pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2", true))()
end)
if not Rayfield then
    pcall(function()
        Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Rayfield/main/source", true))()
    end)
end

if Rayfield then
    local Window = Rayfield:CreateWindow({
        name = "ollie // harbor havoc",
        subtitle = "v6 network",
        sidebarLayout = true,
        configuration = { autoSave = true, autoLoad = true, fileName = "ollie_hh_v6" },
    })

    local TS = Window:CreateTab({ name = "silent" })
    TS:CreateToggle({ name = "silent (mouse+cam)", value = S.Silent, flag = "silent", callback = function(v) S.Silent = v end })
    TS:CreateSlider({ name = "fov", range = {10, 800}, increment = 10, value = S.SilentFOV, flag = "sfov", callback = function(v) S.SilentFOV = v end })
    TS:CreateDropdown({ name = "part", options = {"Head","HumanoidRootPart","UpperTorso","LowerTorso"}, value = S.SilentPart, flag = "spart", callback = function(v) S.SilentPart = v end })
    TS:CreateToggle({ name = "team check", value = S.SilentTeam, flag = "steam", callback = function(v) S.SilentTeam = v end })
    TS:CreateToggle({ name = "wall check", value = S.SilentWall, flag = "swall", callback = function(v) S.SilentWall = v end })
    TS:CreateSection({ name = "predict" })
    TS:CreateToggle({ name = "predict", value = S.Predict, flag = "predict", callback = function(v) S.Predict = v end })
    TS:CreateSlider({ name = "bullet speed", range = {50, 2000}, increment = 10, value = S.BulletSpeed, flag = "bspd", callback = function(v) S.BulletSpeed = v end })

    local TA = Window:CreateTab({ name = "aimbot" })
    TA:CreateToggle({ name = "aimbot TOGGLE", value = S.Aimbot, flag = "aimbot", callback = function(v) S.Aimbot = v end })
    TA:CreateSlider({ name = "fov", range = {10, 800}, increment = 10, value = S.AimbotFOV, flag = "afov", callback = function(v) S.AimbotFOV = v end })
    TA:CreateSlider({ name = "smooth x100", range = {1, 100}, increment = 1, value = math.floor(S.AimbotSmooth*100), flag = "asmooth", callback = function(v) S.AimbotSmooth = v/100 end })
    TA:CreateDropdown({ name = "part", options = {"Head","HumanoidRootPart","UpperTorso","LowerTorso"}, value = S.AimbotPart, flag = "apart", callback = function(v) S.AimbotPart = v end })
    TA:CreateToggle({ name = "team check", value = S.AimbotTeam, flag = "ateam", callback = function(v) S.AimbotTeam = v end })
    TA:CreateToggle({ name = "wall check", value = S.AimbotWall, flag = "awall", callback = function(v) S.AimbotWall = v end })

    local TE = Window:CreateTab({ name = "esp" })
    TE:CreateToggle({ name = "esp", value = S.ESP, flag = "esp", callback = function(v) S.ESP = v end })
    TE:CreateToggle({ name = "box", value = S.ESPBox, flag = "esp_box", callback = function(v) S.ESPBox = v end })
    TE:CreateToggle({ name = "name", value = S.ESPName, flag = "esp_nm", callback = function(v) S.ESPName = v end })
    TE:CreateToggle({ name = "health", value = S.ESPHealth, flag = "esp_hp", callback = function(v) S.ESPHealth = v end })
    TE:CreateToggle({ name = "distance", value = S.ESPDistance, flag = "esp_dst", callback = function(v) S.ESPDistance = v end })
    TE:CreateToggle({ name = "tracer", value = S.ESPTracer, flag = "esp_trc", callback = function(v) S.ESPTracer = v end })
    TE:CreateToggle({ name = "team check", value = S.ESPTeam, flag = "esp_tm", callback = function(v) S.ESPTeam = v end })
    TE:CreateSlider({ name = "max distance", range = {200, 5000}, increment = 100, value = S.ESPMaxDist, flag = "esp_max", callback = function(v) S.ESPMaxDist = v end })

    if not IS_MOBILE then
        UserInput.InputBegan:Connect(function(i, g)
            if not g and i.KeyCode == Enum.KeyCode.RightShift then Rayfield:Toggle() end
        end)
    end
else
    warn("ollie: Rayfield fail — use mobile buttons / defaults")
end

print("ollie v6 ready | mobile=", IS_MOBILE, "| drawing=", HAS_DRAWING)
