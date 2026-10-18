-- ollie // harbor havoc | rayfield gen2 + adaptive predict
-- RightShift — скрыть/показать

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

-- ── config ────────────────────────────────────────────────────────────────────
local S = {
    Silent         = true,
    SilentFOV      = 180,
    SilentPart     = "Head",
    SilentTeam     = true,
    SilentWall     = false,
    BulletSpeed    = 300,   -- studs/s, меняется слайдером

    Aimbot         = false,
    AimbotKey      = Enum.KeyCode.E,
    AimbotFOV      = 180,
    AimbotSmooth   = 0.15,
    AimbotPart     = "Head",
    AimbotTeam     = true,
    AimbotWall     = false,

    ESP            = true,
    ESPBox         = true,
    ESPName        = true,
    ESPHealth      = true,
    ESPDistance    = true,
    ESPTracer      = false,
    ESPTeam        = true,
    ESPMaxDist     = 2000,
}

-- ── velocity tracker ──────────────────────────────────────────────────────────
-- храним позицию каждого игрока с прошлого кадра → считаем velocity
local prevPos = {}
local velocity = {}

RunService.Heartbeat:Connect(function(dt)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not root then prevPos[p] = nil; velocity[p] = Vector3.zero; continue end
        if prevPos[p] then
            velocity[p] = (root.Position - prevPos[p]) / dt
        else
            velocity[p] = Vector3.zero
        end
        prevPos[p] = root.Position
    end
end)

-- ── predict ───────────────────────────────────────────────────────────────────
local function predictPos(p, part)
    local char = p.Character
    if not char then return nil end
    local bp = char:FindFirstChild(part) or char:FindFirstChild("HumanoidRootPart")
    if not bp then return nil end

    local vel  = velocity[p] or Vector3.zero
    local dist = (bp.Position - Camera.CFrame.Position).Magnitude
    local tof  = dist / math.max(S.BulletSpeed, 1)   -- time of flight

    -- адаптивный оффсет: velocity × tof
    return bp.Position + vel * tof
end

-- ── utils ─────────────────────────────────────────────────────────────────────
local function isAlive(p)
    local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function sameTeam(p)
    return LP.Team and p.Team and LP.Team == p.Team
end

local function wallCheck(pos)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LP.Character or workspace}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local dir = pos - Camera.CFrame.Position
    return workspace:Raycast(Camera.CFrame.Position, dir, params) == nil
end

local function getBestTarget(fov, part, teamCheck, wallCheck_)
    local best, bestDist = nil, fov
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not isAlive(p) then continue end
        if teamCheck and sameTeam(p) then continue end
        local predicted = predictPos(p, part)
        if not predicted then continue end
        if wallCheck_ and not wallCheck(predicted) then continue end
        local sp, vis = Camera:WorldToViewportPoint(predicted)
        if not vis then continue end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d < bestDist then bestDist = d; best = p end
    end
    return best
end

-- ── silent aim hook ───────────────────────────────────────────────────────────
local Remotes    = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local FireWeapon = Remotes:WaitForChild("FireWeapon")

local mt = getrawmetatable(game)
setreadonly(mt, false)
local origNamecall = mt.__namecall
mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" and self == FireWeapon and S.Silent then
        local args = {...}
        local target = getBestTarget(S.SilentFOV, S.SilentPart, S.SilentTeam, S.SilentWall)
        if target then
            local predicted = predictPos(target, S.SilentPart)
            if predicted then
                for i, v in ipairs(args) do
                    if typeof(v) == "CFrame" then
                        args[i] = CFrame.new(predicted)
                        break
                    elseif typeof(v) == "Vector3" then
                        args[i] = predicted
                        break
                    end
                end
            end
        end
        return origNamecall(self, table.unpack(args))
    end
    return origNamecall(self, ...)
end)
setreadonly(mt, true)

-- ── aimbot ────────────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    if not S.Aimbot then return end
    if not UserInput:IsKeyDown(S.AimbotKey) then return end
    local target = getBestTarget(S.AimbotFOV, S.AimbotPart, S.AimbotTeam, S.AimbotWall)
    if not target then return end
    local predicted = predictPos(target, S.AimbotPart)
    if not predicted then return end
    if S.AimbotWall and not wallCheck(predicted) then return end
    Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, predicted), S.AimbotSmooth)
end)

-- ── esp ───────────────────────────────────────────────────────────────────────
local espCache = {}

local function clearESP(p)
    if espCache[p] then
        for _, v in pairs(espCache[p]) do pcall(function() v:Remove() end) end
        espCache[p] = nil
    end
end

local function initESP(p)
    clearESP(p)
    local function d(type) return Drawing.new(type) end
    local box    = d("Square"); box.Filled=false; box.Color=Color3.fromRGB(255,50,50); box.Thickness=1
    local name_  = d("Text");   name_.Center=true; name_.Outline=true; name_.Size=13; name_.Color=Color3.fromRGB(255,255,255)
    local hbBg   = d("Square"); hbBg.Filled=true;  hbBg.Color=Color3.fromRGB(0,0,0); hbBg.Thickness=1
    local hb     = d("Square"); hb.Filled=true;    hb.Color=Color3.fromRGB(60,220,60)
    local dist_  = d("Text");   dist_.Center=true; dist_.Outline=true; dist_.Size=11; dist_.Color=Color3.fromRGB(200,200,200)
    local tracer = d("Line");   tracer.Thickness=1; tracer.Color=Color3.fromRGB(255,50,50)
    espCache[p] = {box=box,name=name_,hbBg=hbBg,hb=hb,dist=dist_,tracer=tracer}
end

RunService.RenderStepped:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not espCache[p] then initESP(p) end
        local e   = espCache[p]
        local on  = S.ESP and isAlive(p) and not (S.ESPTeam and sameTeam(p))
        local char = p.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")

        if not on or not root or not hum then
            for _, v in pairs(e) do v.Visible=false end
            continue
        end

        local rp, vis = Camera:WorldToViewportPoint(root.Position)
        if not vis or (root.Position-Camera.CFrame.Position).Magnitude > S.ESPMaxDist then
            for _, v in pairs(e) do v.Visible=false end
            continue
        end

        local topRaw = head and Camera:WorldToViewportPoint(head.Position+Vector3.new(0,.7,0)) or rp
        local botRaw = Camera:WorldToViewportPoint(root.Position-Vector3.new(0,2.8,0))
        local top    = Vector2.new(topRaw.X, topRaw.Y)
        local bot    = Vector2.new(botRaw.X, botRaw.Y)
        local h      = math.abs(bot.Y-top.Y)
        local w      = h*0.5
        local x      = top.X-w/2

        e.box.Visible   = S.ESPBox
        e.box.Position  = Vector2.new(x,top.Y)
        e.box.Size      = Vector2.new(w,h)

        e.name.Visible  = S.ESPName
        e.name.Position = Vector2.new(top.X, top.Y-15)
        e.name.Text     = p.DisplayName

        local hp = math.clamp(hum.Health/math.max(hum.MaxHealth,1),0,1)
        e.hbBg.Visible  = S.ESPHealth
        e.hbBg.Position = Vector2.new(x-6, top.Y)
        e.hbBg.Size     = Vector2.new(3,h)
        e.hb.Visible    = S.ESPHealth
        e.hb.Position   = Vector2.new(x-6, top.Y+h*(1-hp))
        e.hb.Size       = Vector2.new(3, h*hp)
        e.hb.Color      = Color3.fromRGB((1-hp)*255, hp*255, 0)

        e.dist.Visible  = S.ESPDistance
        e.dist.Position = Vector2.new(top.X, bot.Y+2)
        e.dist.Text     = math.floor((root.Position-Camera.CFrame.Position).Magnitude).."u"

        e.tracer.Visible = S.ESPTracer
        e.tracer.From    = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        e.tracer.To      = Vector2.new(rp.X,rp.Y)
    end
end)

Players.PlayerRemoving:Connect(clearESP)

-- ── rayfield ui ───────────────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local Window = Rayfield:CreateWindow({
    name          = "ollie // harbor havoc",
    subtitle      = "bench lit",
    sidebarLayout = true,
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "ollie_hh",
    },
})

-- ── tab: silent aim ───────────────────────────────────────────────────────────
local TabS = Window:CreateTab({ name = "silent" })

TabS:CreateToggle({
    name     = "silent aim",
    value    = S.Silent,
    flag     = "silent",
    callback = function(v) S.Silent = v end,
})

TabS:CreateSlider({
    name      = "fov",
    range     = { 10, 800 },
    increment = 10,
    suffix    = "px",
    value     = S.SilentFOV,
    flag      = "silent_fov",
    callback  = function(v) S.SilentFOV = v end,
})

TabS:CreateDropdown({
    name     = "target part",
    options  = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
    value    = S.SilentPart,
    flag     = "silent_part",
    callback = function(v) S.SilentPart = v end,
})

TabS:CreateToggle({
    name     = "team check",
    value    = S.SilentTeam,
    flag     = "silent_team",
    callback = function(v) S.SilentTeam = v end,
})

TabS:CreateToggle({
    name     = "wall check",
    value    = S.SilentWall,
    flag     = "silent_wall",
    callback = function(v) S.SilentWall = v end,
})

TabS:CreateSection({ name = "predict" })

TabS:CreateSlider({
    name      = "bullet speed (studs/s)",
    range     = { 50, 2000 },
    increment = 10,
    suffix    = "u/s",
    value     = S.BulletSpeed,
    flag      = "bullet_speed",
    callback  = function(v) S.BulletSpeed = v end,
})

-- ── tab: aimbot ───────────────────────────────────────────────────────────────
local TabA = Window:CreateTab({ name = "aimbot" })

TabA:CreateToggle({
    name     = "aimbot",
    value    = S.Aimbot,
    flag     = "aimbot",
    callback = function(v) S.Aimbot = v end,
})

TabA:CreateKeybind({
    name     = "hold key",
    value    = S.AimbotKey,
    flag     = "aim_key",
    callback = function(k) S.AimbotKey = k end,
})

TabA:CreateSlider({
    name      = "fov",
    range     = { 10, 800 },
    increment = 10,
    suffix    = "px",
    value     = S.AimbotFOV,
    flag      = "aim_fov",
    callback  = function(v) S.AimbotFOV = v end,
})

TabA:CreateSlider({
    name      = "smooth x100",
    range     = { 1, 100 },
    increment = 1,
    value     = math.floor(S.AimbotSmooth * 100),
    flag      = "aim_smooth",
    callback  = function(v) S.AimbotSmooth = v / 100 end,
})

TabA:CreateDropdown({
    name     = "target part",
    options  = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
    value    = S.AimbotPart,
    flag     = "aim_part",
    callback = function(v) S.AimbotPart = v end,
})

TabA:CreateToggle({
    name     = "team check",
    value    = S.AimbotTeam,
    flag     = "aim_team",
    callback = function(v) S.AimbotTeam = v end,
})

TabA:CreateToggle({
    name     = "wall check",
    value    = S.AimbotWall,
    flag     = "aim_wall",
    callback = function(v) S.AimbotWall = v end,
})

-- ── tab: esp ──────────────────────────────────────────────────────────────────
local TabE = Window:CreateTab({ name = "esp" })

TabE:CreateToggle({ name="esp",        value=S.ESP,         flag="esp",     callback=function(v) S.ESP=v end })
TabE:CreateToggle({ name="box",        value=S.ESPBox,      flag="esp_box", callback=function(v) S.ESPBox=v end })
TabE:CreateToggle({ name="name",       value=S.ESPName,     flag="esp_nm",  callback=function(v) S.ESPName=v end })
TabE:CreateToggle({ name="health",     value=S.ESPHealth,   flag="esp_hp",  callback=function(v) S.ESPHealth=v end })
TabE:CreateToggle({ name="distance",   value=S.ESPDistance, flag="esp_dst", callback=function(v) S.ESPDistance=v end })
TabE:CreateToggle({ name="tracer",     value=S.ESPTracer,   flag="esp_trc", callback=function(v) S.ESPTracer=v end })
TabE:CreateToggle({ name="team check", value=S.ESPTeam,     flag="esp_tm",  callback=function(v) S.ESPTeam=v end })

TabE:CreateSlider({
    name      = "max distance",
    range     = { 200, 5000 },
    increment = 100,
    suffix    = "u",
    value     = S.ESPMaxDist,
    flag      = "esp_max",
    callback  = function(v) S.ESPMaxDist = v end,
})

-- RightShift toggle
UserInput.InputBegan:Connect(function(i, g)
    if g then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        Rayfield:Toggle()
    end
end)
