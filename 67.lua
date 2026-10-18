-- ollie // harbor havoc v4
-- fixed: esp bbox, silent hook, vehicle targeting, velocity tracking

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

-- ── config ────────────────────────────────────────────────────────────────────
local S = {
    Silent       = true,
    SilentFOV    = 180,
    SilentPart   = "Head",
    SilentTeam   = true,
    SilentWall   = false,
    BulletSpeed  = 300,

    Aimbot       = false,
    AimbotKey    = Enum.KeyCode.E,
    AimbotFOV    = 180,
    AimbotSmooth = 0.15,
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

-- ── velocity cache ────────────────────────────────────────────────────────────
local velMap  = {}  -- [instance] = Vector3 velocity
local prevMap = {}  -- [instance] = Vector3 last position

RunService.Heartbeat:Connect(function(dt)
    if dt <= 0 then return end
    -- игроки
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not root then velMap[p] = Vector3.zero; prevMap[p] = nil; continue end
        velMap[p]  = prevMap[p] and (root.Position - prevMap[p]) / dt or Vector3.zero
        prevMap[p] = root.Position
    end
    -- vehicle chars в Folder
    local folder = workspace:FindFirstChild("Folder")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            local root = model:FindFirstChild("HumanoidRootPart")
                      or (model:IsA("Model") and model.PrimaryPart)
            if not root then continue end
            velMap[model]  = prevMap[model] and (root.Position - prevMap[model]) / dt or Vector3.zero
            prevMap[model] = root.Position
        end
    end
end)

-- ── target system ─────────────────────────────────────────────────────────────
-- возвращает список всех живых целей {root, vel, name, hum?, team?}
local function getTargets()
    local list = {}

    -- обычные игроки (пешком)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local char = p.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end
        table.insert(list, {
            root  = root,
            vel   = velMap[p] or Vector3.zero,
            name  = p.DisplayName,
            hum   = hum,
            team  = p.Team,
            p     = p,
        })
    end

    -- персонажи/транспорт в workspace.Folder (игроки в транспорте + сами корабли/самолёты)
    local folder = workspace:FindFirstChild("Folder")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if not model:IsA("Model") then continue end

            -- если это персонаж игрока — уже добавлен выше, пропускаем
            local isPlayerChar = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == model then isPlayerChar = true; break end
            end
            if isPlayerChar then continue end

            local root = model:FindFirstChild("HumanoidRootPart")
                      or model.PrimaryPart
                      or model:FindFirstChildWhichIsA("BasePart")
            if not root then continue end

            -- пропускаем мелкие объекты (декор)
            if root:IsA("BasePart") and root.Size.Magnitude < 4 then continue end

            local hum = model:FindFirstChildOfClass("Humanoid")

            table.insert(list, {
                root  = root,
                vel   = velMap[model] or Vector3.zero,
                name  = model.Name,
                hum   = hum,
                team  = nil,  -- транспорт не имеет Team напрямую
                p     = nil,
                model = model,
            })
        end
    end

    return list
end

-- предикт позиции с учётом velocity и дистанции
local function predictedPos(t, offsetPart)
    local base
    if t.p then
        local char = t.p.Character
        base = char and (char:FindFirstChild(offsetPart) or t.root)
        base = base and base.Position or t.root.Position
    else
        base = t.root.Position
    end
    local dist = (base - Camera.CFrame.Position).Magnitude
    local tof  = dist / math.max(S.BulletSpeed, 1)
    return base + t.vel * tof
end

local function sameTeam(t)
    if not t.team then return false end
    return LP.Team and t.team == LP.Team
end

local function wallClear(pos)
    local params = RaycastParams.new()
    local lpChar = LP.Character
    params.FilterDescendantsInstances = lpChar and {lpChar} or {}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local dir = pos - Camera.CFrame.Position
    return workspace:Raycast(Camera.CFrame.Position, dir, params) == nil
end

-- лучшая цель по FOV
local function getBest(fov, part, teamCheck, doWall)
    local best, bestD = nil, fov
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    for _, t in ipairs(getTargets()) do
        if teamCheck and sameTeam(t) then continue end
        local pos  = predictedPos(t, part)
        if doWall and not wallClear(pos) then continue end
        local sp, vis = Camera:WorldToViewportPoint(pos)
        if not vis then continue end
        local d = math.sqrt((sp.X-cx)^2 + (sp.Y-cy)^2)
        if d < bestD then bestD = d; best = t end
    end
    return best
end

-- ── silent aim ────────────────────────────────────────────────────────────────
local Remotes    = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
local FireWeapon = Remotes and Remotes:WaitForChild("FireWeapon", 10)

if FireWeapon then
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local origNC = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        if getnamecallmethod() == "FireServer" and self == FireWeapon and S.Silent then
            local args   = {...}
            local target = getBest(S.SilentFOV, S.SilentPart, S.SilentTeam, S.SilentWall)
            if target then
                local pos = predictedPos(target, S.SilentPart)
                for i, v in ipairs(args) do
                    if typeof(v) == "CFrame" then
                        args[i] = CFrame.new(pos); break
                    elseif typeof(v) == "Vector3" then
                        args[i] = pos; break
                    end
                end
            end
            return origNC(self, table.unpack(args))
        end
        return origNC(self, ...)
    end)
    setreadonly(mt, true)
else
    warn("ollie: FireWeapon remote not found")
end

-- ── aimbot ────────────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    if not S.Aimbot then return end
    if not UserInput:IsKeyDown(S.AimbotKey) then return end
    local t = getBest(S.AimbotFOV, S.AimbotPart, S.AimbotTeam, S.AimbotWall)
    if not t then return end
    local pos  = predictedPos(t, S.AimbotPart)
    local goal = CFrame.new(Camera.CFrame.Position, pos)
    Camera.CFrame = Camera.CFrame:Lerp(goal, S.AimbotSmooth)
end)

-- ── esp ───────────────────────────────────────────────────────────────────────
local espCache = {}

local function clearESP(key)
    if espCache[key] then
        for _, v in pairs(espCache[key]) do pcall(function() v:Remove() end) end
        espCache[key] = nil
    end
end

local function newDrawing(t, props)
    local d = Drawing.new(t)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function initESP(key)
    clearESP(key)
    espCache[key] = {
        box    = newDrawing("Square", {Filled=false, Color=Color3.fromRGB(255,50,50),  Thickness=1, Visible=false}),
        name   = newDrawing("Text",   {Center=true,  Color=Color3.fromRGB(255,255,255), Size=13, Outline=true, Visible=false}),
        hbBg   = newDrawing("Square", {Filled=true,  Color=Color3.fromRGB(0,0,0),       Thickness=1, Visible=false}),
        hb     = newDrawing("Square", {Filled=true,  Color=Color3.fromRGB(60,220,60),   Thickness=1, Visible=false}),
        dist   = newDrawing("Text",   {Center=true,  Color=Color3.fromRGB(200,200,200), Size=11, Outline=true, Visible=false}),
        tracer = newDrawing("Line",   {Thickness=1,  Color=Color3.fromRGB(255,50,50),   Visible=false}),
    }
end

-- ── bbox fix: используем угловые точки модели ─────────────────────────────────
local function getScreenBBox(root, char)
    -- собираем все BasePart в персонаже/модели
    local parts = {}
    if char then
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") then table.insert(parts, v) end
        end
    end
    if #parts == 0 then table.insert(parts, root) end

    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local anyVis = false
    for _, part in ipairs(parts) do
        local sp, vis = Camera:WorldToViewportPoint(part.Position)
        if vis then
            anyVis = true
            if sp.X < minX then minX = sp.X end
            if sp.Y < minY then minY = sp.Y end
            if sp.X > maxX then maxX = sp.X end
            if sp.Y > maxY then maxY = sp.Y end
        end
    end
    if not anyVis then return nil end

    -- clamp минимальный размер чтобы бокс не был огромным вблизи
    local w = math.max(maxX - minX, 10)
    local h = math.max(maxY - minY, 10)
    -- clamp максимум по высоте экрана чтобы не распухал вдали
    h = math.min(h, Camera.ViewportSize.Y * 0.8)
    w = math.min(w, Camera.ViewportSize.X * 0.8)
    return minX, minY, w, h
end

RunService.RenderStepped:Connect(function()
    local targets = getTargets()

    -- строим set ключей живых целей
    local alive = {}
    for _, t in ipairs(targets) do
        local key = t.p or t.model or t.root
        alive[key] = t
    end

    -- убираем ESP мёртвых
    for key in pairs(espCache) do
        if not alive[key] then clearESP(key) end
    end

    for key, t in pairs(alive) do
        if not espCache[key] then initESP(key) end
        local e   = espCache[key]
        local cam = Camera.CFrame.Position
        local dist3d = (t.root.Position - cam).Magnitude

        local show = S.ESP
            and not (S.ESPTeam and sameTeam(t))
            and dist3d <= S.ESPMaxDist
            and (t.hum == nil or t.hum.Health > 0)

        if not show then
            for _, v in pairs(e) do v.Visible = false end
            continue
        end

        local rsp, rvis = Camera:WorldToViewportPoint(t.root.Position)
        if not rvis then
            for _, v in pairs(e) do v.Visible = false end
            continue
        end

        local bx, by, bw, bh = getScreenBBox(t.root, t.model or (t.p and t.p.Character))
        if not bx then
            for _, v in pairs(e) do v.Visible = false end
            continue
        end

        -- box
        e.box.Visible  = S.ESPBox
        e.box.Position = Vector2.new(bx, by)
        e.box.Size     = Vector2.new(bw, bh)

        -- name
        e.name.Visible  = S.ESPName
        e.name.Position = Vector2.new(bx + bw/2, by - 15)
        e.name.Text     = t.name

        -- health (только для гуманоидов)
        if t.hum and t.hum.MaxHealth > 0 then
            local hp = math.clamp(t.hum.Health / t.hum.MaxHealth, 0, 1)
            e.hbBg.Visible  = S.ESPHealth
            e.hbBg.Position = Vector2.new(bx - 6, by)
            e.hbBg.Size     = Vector2.new(3, bh)
            e.hb.Visible    = S.ESPHealth
            e.hb.Position   = Vector2.new(bx - 6, by + bh*(1-hp))
            e.hb.Size       = Vector2.new(3, bh*hp)
            e.hb.Color      = Color3.fromRGB((1-hp)*255, hp*255, 0)
        else
            e.hbBg.Visible = false
            e.hb.Visible   = false
        end

        -- distance
        e.dist.Visible  = S.ESPDistance
        e.dist.Position = Vector2.new(bx + bw/2, by + bh + 2)
        e.dist.Text     = math.floor(dist3d) .. "u"

        -- tracer
        e.tracer.Visible = S.ESPTracer
        e.tracer.From    = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        e.tracer.To      = Vector2.new(rsp.X, rsp.Y)
    end
end)

Players.PlayerRemoving:Connect(function(p)
    clearESP(p)
    velMap[p]  = nil
    prevMap[p] = nil
end)

-- ── rayfield ui ───────────────────────────────────────────────────────────────
local Rayfield
pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2", true))()
end)
if not Rayfield then
    pcall(function()
        Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Rayfield/main/source", true))()
    end)
end
if not Rayfield then warn("ollie: Rayfield failed"); return end

local Window = Rayfield:CreateWindow({
    name          = "ollie // harbor havoc",
    subtitle      = "v4",
    sidebarLayout = true,
    configuration = { autoSave=true, autoLoad=true, fileName="ollie_hh" },
})

-- silent
local TS = Window:CreateTab({ name = "silent" })
TS:CreateToggle({ name="silent aim",   value=S.Silent,      flag="silent",      callback=function(v) S.Silent=v end })
TS:CreateSlider({ name="fov", range={10,800}, increment=10, suffix="px", value=S.SilentFOV, flag="sfov", callback=function(v) S.SilentFOV=v end })
TS:CreateDropdown({ name="part", options={"Head","HumanoidRootPart","UpperTorso","LowerTorso"}, value=S.SilentPart, flag="spart", callback=function(v) S.SilentPart=v end })
TS:CreateToggle({ name="team check",   value=S.SilentTeam,  flag="steam",       callback=function(v) S.SilentTeam=v end })
TS:CreateToggle({ name="wall check",   value=S.SilentWall,  flag="swall",       callback=function(v) S.SilentWall=v end })
TS:CreateSection({ name="predict" })
TS:CreateSlider({ name="bullet speed", range={50,2000}, increment=10, suffix="u/s", value=S.BulletSpeed, flag="bspd", callback=function(v) S.BulletSpeed=v end })

-- aimbot
local TA = Window:CreateTab({ name = "aimbot" })
TA:CreateToggle({ name="aimbot",       value=S.Aimbot,      flag="aimbot",      callback=function(v) S.Aimbot=v end })
TA:CreateKeybind({ name="hold key",    value=S.AimbotKey,   flag="akey",        callback=function(k) S.AimbotKey=k end })
TA:CreateSlider({ name="fov", range={10,800}, increment=10, suffix="px", value=S.AimbotFOV, flag="afov", callback=function(v) S.AimbotFOV=v end })
TA:CreateSlider({ name="smooth x100",  range={1,100}, increment=1, value=math.floor(S.AimbotSmooth*100), flag="asmooth", callback=function(v) S.AimbotSmooth=v/100 end })
TA:CreateDropdown({ name="part", options={"Head","HumanoidRootPart","UpperTorso","LowerTorso"}, value=S.AimbotPart, flag="apart", callback=function(v) S.AimbotPart=v end })
TA:CreateToggle({ name="team check",   value=S.AimbotTeam,  flag="ateam",       callback=function(v) S.AimbotTeam=v end })
TA:CreateToggle({ name="wall check",   value=S.AimbotWall,  flag="awall",       callback=function(v) S.AimbotWall=v end })

-- esp
local TE = Window:CreateTab({ name = "esp" })
TE:CreateToggle({ name="esp",          value=S.ESP,         flag="esp",         callback=function(v) S.ESP=v end })
TE:CreateToggle({ name="box",          value=S.ESPBox,      flag="esp_box",     callback=function(v) S.ESPBox=v end })
TE:CreateToggle({ name="name",         value=S.ESPName,     flag="esp_nm",      callback=function(v) S.ESPName=v end })
TE:CreateToggle({ name="health",       value=S.ESPHealth,   flag="esp_hp",      callback=function(v) S.ESPHealth=v end })
TE:CreateToggle({ name="distance",     value=S.ESPDistance, flag="esp_dst",     callback=function(v) S.ESPDistance=v end })
TE:CreateToggle({ name="tracer",       value=S.ESPTracer,   flag="esp_trc",     callback=function(v) S.ESPTracer=v end })
TE:CreateToggle({ name="team check",   value=S.ESPTeam,     flag="esp_tm",      callback=function(v) S.ESPTeam=v end })
TE:CreateSlider({ name="max distance", range={200,5000}, increment=100, suffix="u", value=S.ESPMaxDist, flag="esp_max", callback=function(v) S.ESPMaxDist=v end })

UserInput.InputBegan:Connect(function(i, g)
    if g then return end
    if i.KeyCode == Enum.KeyCode.RightShift then Rayfield:Toggle() end
end)
