-- ollie // harbor havoc
-- silent aim + aimbot + esp
-- self-contained, no external config required

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

-- ── настройки ─────────────────────────────────────────────────────────────────
local S = {
    -- silent aim
    Silent        = true,
    SilentFOV     = 180,
    SilentPart    = "Head",
    SilentTeam    = true,
    SilentWall    = false,

    -- aimbot
    Aimbot        = false,
    AimbotKey     = Enum.KeyCode.E,
    AimbotFOV     = 180,
    AimbotSmooth  = 0.15,
    AimbotPart    = "Head",
    AimbotTeam    = true,
    AimbotWall    = false,

    -- esp
    ESP           = true,
    ESPBox        = true,
    ESPName       = true,
    ESPHealth     = true,
    ESPDistance   = true,
    ESPTracer     = false,
    ESPTeam       = true,
    ESPMaxDist    = 2000,
}

-- ── утилиты ───────────────────────────────────────────────────────────────────
local function getChar(p)
    return p and p.Character
end

local function getRoot(p)
    local c = getChar(p)
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getPart(p, name)
    local c = getChar(p)
    return c and (c:FindFirstChild(name) or c:FindFirstChild("HumanoidRootPart"))
end

local function getHum(p)
    local c = getChar(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function isAlive(p)
    local h = getHum(p)
    return h and h.Health > 0
end

local function sameTeam(p)
    return LP.Team and p.Team and LP.Team == p.Team
end

local function wallCheck(pos)
    local origin = Camera.CFrame.Position
    local dir    = (pos - origin)
    local ray    = RaycastParams.new()
    ray.FilterDescendantsInstances = {workspace.Folder, getChar(LP)}
    ray.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(origin, dir, ray)
    return res == nil
end

local function getFOVTarget(fov, part)
    local best, bestDist = nil, fov
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not isAlive(p) then continue end
        if S.AimbotTeam and sameTeam(p) then continue end
        local bp = getPart(p, part)
        if not bp then continue end
        local pos, vis = Camera:WorldToViewportPoint(bp.Position)
        if not vis then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if dist < bestDist then
            bestDist = dist
            best     = p
        end
    end
    return best
end

local function getSilentTarget(fov, part)
    local best, bestDist = nil, fov
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not isAlive(p) then continue end
        if S.SilentTeam and sameTeam(p) then continue end
        local bp = getPart(p, part)
        if not bp then continue end
        if S.SilentWall and not wallCheck(bp.Position) then continue end
        local pos, vis = Camera:WorldToViewportPoint(bp.Position)
        if not vis then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if dist < bestDist then
            bestDist = dist
            best     = p
        end
    end
    return best
end

-- ── silent aim hook ───────────────────────────────────────────────────────────
local FireWeapon = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    :WaitForChild("FireWeapon")

local oldFire
oldFire = FireWeapon.OnClientEvent -- нет, нам нужно перехватить :FireServer
-- hookfunction для перехвата исходящего :FireServer
local mt = getrawmetatable(game)
local old_index = mt.__index
local old_newindex = mt.__newindex
setreadonly(mt, false)

-- перехватываем через hookfunction на FireServer
local success = pcall(function()
    local orig = FireWeapon.FireServer
    hookfunction(orig, function(self, ...)
        if self ~= FireWeapon then return orig(self, ...) end
        if not S.Silent then return orig(self, ...) end
        local args = {...}
        local target = getSilentTarget(S.SilentFOV, S.SilentPart)
        if target then
            local bp = getPart(target, S.SilentPart)
            if bp then
                -- подменяем позицию в аргументах если есть CFrame/Vector3
                for i, v in ipairs(args) do
                    if typeof(v) == "CFrame" then
                        args[i] = CFrame.new(bp.Position)
                        break
                    elseif typeof(v) == "Vector3" then
                        args[i] = bp.Position
                        break
                    end
                end
            end
        end
        return orig(self, table.unpack(args))
    end)
end)

setreadonly(mt, true)

if not success then
    -- фоллбэк: Nam hook через __namecall
    setreadonly(mt, false)
    local namecall_orig = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == FireWeapon and S.Silent then
            local args = {...}
            local target = getSilentTarget(S.SilentFOV, S.SilentPart)
            if target then
                local bp = getPart(target, S.SilentPart)
                if bp then
                    for i, v in ipairs(args) do
                        if typeof(v) == "CFrame" then
                            args[i] = CFrame.new(bp.Position)
                            break
                        elseif typeof(v) == "Vector3" then
                            args[i] = bp.Position
                            break
                        end
                    end
                end
            end
            return namecall_orig(self, table.unpack(args))
        end
        return namecall_orig(self, ...)
    end)
    setreadonly(mt, false)
end

-- ── aimbot ────────────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    if not S.Aimbot then return end
    if not UserInput:IsKeyDown(S.AimbotKey) then return end
    local target = getFOVTarget(S.AimbotFOV, S.AimbotPart)
    if not target then return end
    local bp = getPart(target, S.AimbotPart)
    if not bp then return end
    if S.AimbotWall and not wallCheck(bp.Position) then return end
    local goal = CFrame.new(Camera.CFrame.Position, bp.Position)
    Camera.CFrame = Camera.CFrame:Lerp(goal, S.AimbotSmooth)
end)

-- ── esp ───────────────────────────────────────────────────────────────────────
local espObjects = {}

local function removeESP(p)
    if espObjects[p] then
        for _, v in pairs(espObjects[p]) do
            pcall(function() v:Remove() end)
        end
        espObjects[p] = nil
    end
end

local function makeESP(p)
    removeESP(p)
    local t = {}

    -- box
    local box = Drawing.new("Square")
    box.Visible   = false
    box.Filled    = false
    box.Color     = Color3.fromRGB(255, 60, 60)
    box.Thickness = 1
    t.box = box

    -- name
    local name = Drawing.new("Text")
    name.Visible  = false
    name.Center   = true
    name.Outline  = true
    name.Size     = 13
    name.Color    = Color3.fromRGB(255, 255, 255)
    t.name = name

    -- health bar
    local hbBg = Drawing.new("Square")
    hbBg.Visible   = false
    hbBg.Filled    = true
    hbBg.Color     = Color3.fromRGB(0, 0, 0)
    hbBg.Thickness = 1
    t.hbBg = hbBg

    local hb = Drawing.new("Square")
    hb.Visible   = false
    hb.Filled    = true
    hb.Color     = Color3.fromRGB(60, 220, 60)
    hb.Thickness = 1
    t.hb = hb

    -- distance
    local dist = Drawing.new("Text")
    dist.Visible = false
    dist.Center  = true
    dist.Outline = true
    dist.Size    = 11
    dist.Color   = Color3.fromRGB(220, 220, 220)
    t.dist = dist

    -- tracer
    local tracer = Drawing.new("Line")
    tracer.Visible   = false
    tracer.Thickness = 1
    tracer.Color     = Color3.fromRGB(255, 60, 60)
    t.tracer = tracer

    espObjects[p] = t
end

local function updateESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not espObjects[p] then makeESP(p) end

        local t   = espObjects[p]
        local vis = S.ESP and isAlive(p)
        if S.ESPTeam and sameTeam(p) then vis = false end

        if not vis then
            for _, v in pairs(t) do v.Visible = false end
            continue
        end

        local char = getChar(p)
        local root = getRoot(p)
        local hum  = getHum(p)
        if not char or not root or not hum then
            for _, v in pairs(t) do v.Visible = false end
            continue
        end

        local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
        if not onScreen then
            for _, v in pairs(t) do v.Visible = false end
            continue
        end

        local dist3d = (root.Position - Camera.CFrame.Position).Magnitude
        if dist3d > S.ESPMaxDist then
            for _, v in pairs(t) do v.Visible = false end
            continue
        end

        -- вычисляем bbox через голову и ноги
        local head    = char:FindFirstChild("Head")
        local hrp     = root
        local topPos  = head and Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0)) or rootPos
        local botPos  = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.8, 0))

        local top = Vector2.new(topPos.X, topPos.Y)
        local bot = Vector2.new(botPos.X, botPos.Y)
        local h   = math.abs(bot.Y - top.Y)
        local w   = h * 0.5
        local x   = top.X - w / 2
        local y   = top.Y

        -- box
        t.box.Visible   = S.ESPBox
        t.box.Position  = Vector2.new(x, y)
        t.box.Size      = Vector2.new(w, h)

        -- name
        t.name.Visible  = S.ESPName
        t.name.Position = Vector2.new(top.X, y - 15)
        t.name.Text     = p.DisplayName

        -- health
        local hp     = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local hbH    = h
        local hbX    = x - 6
        t.hbBg.Visible  = S.ESPHealth
        t.hbBg.Position = Vector2.new(hbX, y)
        t.hbBg.Size     = Vector2.new(3, hbH)
        t.hb.Visible    = S.ESPHealth
        t.hb.Position   = Vector2.new(hbX, y + hbH * (1 - hp))
        t.hb.Size       = Vector2.new(3, hbH * hp)
        t.hb.Color      = Color3.fromRGB(math.floor((1 - hp) * 255), math.floor(hp * 255), 0)

        -- distance
        t.dist.Visible  = S.ESPDistance
        t.dist.Position = Vector2.new(top.X, bot.Y + 2)
        t.dist.Text     = math.floor(dist3d) .. "u"

        -- tracer
        t.tracer.Visible = S.ESPTracer
        t.tracer.From    = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        t.tracer.To      = Vector2.new(rootPos.X, rootPos.Y)
    end
end

Players.PlayerRemoving:Connect(removeESP)
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.5)
        makeESP(p)
    end)
end)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then makeESP(p) end
end

RunService.RenderStepped:Connect(updateESP)

-- ── ui ────────────────────────────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "ollie_hh"
ScreenGui.ResetOnSpawn  = false
ScreenGui.DisplayOrder  = 999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = LP.PlayerGui end

local function mkFrame(parent, size, pos, color, radius)
    local f = Instance.new("Frame", parent)
    f.Size            = size
    f.Position        = pos
    f.BackgroundColor3 = color or Color3.fromRGB(14, 14, 18)
    f.BorderSizePixel = 0
    if radius then
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, radius)
    end
    return f
end

local function mkLabel(parent, text, size, color, pos)
    local l = Instance.new("TextLabel", parent)
    l.Size                  = size
    l.Position              = pos or UDim2.new(0, 0, 0, 0)
    l.BackgroundTransparency = 1
    l.Font                  = Enum.Font.GothamMedium
    l.TextSize              = 12
    l.TextColor3            = color or Color3.fromRGB(220, 220, 230)
    l.TextXAlignment        = Enum.TextXAlignment.Left
    l.Text                  = text
    return l
end

local function mkToggle(parent, label, state, yOff, onChange)
    local row = mkFrame(parent, UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, yOff), Color3.fromRGB(20, 20, 26), 4)
    mkLabel(row, label, UDim2.new(1, -36, 1, 0), nil, UDim2.new(0, 8, 0, 0))

    local btn = mkFrame(row, UDim2.new(0, 28, 0, 14), UDim2.new(1, -36, 0.5, -7), state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70), 7)
    local knob = mkFrame(btn, UDim2.new(0, 10, 0, 10), UDim2.new(state and 1 or 0, state and -12 or 2, 0.5, -5), Color3.fromRGB(255, 255, 255), 5)

    local on = state
    btn.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        on = not on
        btn.BackgroundColor3 = on and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(60, 60, 70)
        knob.Position = UDim2.new(on and 1 or 0, on and -12 or 2, 0.5, -5)
        onChange(on)
    end)
    return row
end

-- окно
local win = mkFrame(ScreenGui, UDim2.fromOffset(240, 460), UDim2.new(0, 16, 0.5, -230), Color3.fromRGB(14, 14, 18), 8)

-- заголовок
local title = mkFrame(win, UDim2.new(1, 0, 0, 30), UDim2.new(0,0,0,0), Color3.fromRGB(10, 10, 14), 8)
mkLabel(title, "ollie // harbor havoc", UDim2.new(1,-8,1,0), Color3.fromRGB(180,180,200), UDim2.new(0,8,0,0))

-- drag
local dragging, dragStart, startPos
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = i.Position
        startPos  = win.Position
    end
end)
UserInput.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = i.Position - dragStart
        win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInput.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- скрыть/показать RightShift
local hidden = false
UserInput.InputBegan:Connect(function(i, g)
    if g then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        hidden = not hidden
        win.Visible = not hidden
    end
end)

-- контент
local scroll = Instance.new("ScrollingFrame", win)
scroll.Size             = UDim2.new(1, 0, 1, -34)
scroll.Position         = UDim2.new(0, 0, 0, 32)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel  = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
scroll.CanvasSize       = UDim2.new(0, 0, 0, 0)

local layout = Instance.new("UIListLayout", scroll)
layout.Padding         = UDim.new(0, 4)
layout.SortOrder       = Enum.SortOrder.LayoutOrder

local function section(name)
    local s = Instance.new("TextLabel", scroll)
    s.Size                  = UDim2.new(1, -16, 0, 18)
    s.BackgroundTransparency = 1
    s.Font                  = Enum.Font.GothamBold
    s.TextSize              = 10
    s.TextColor3            = Color3.fromRGB(100, 120, 180)
    s.TextXAlignment        = Enum.TextXAlignment.Left
    s.Text                  = "  " .. string.upper(name)
    s.LayoutOrder           = 0
    return s
end

local function tog(lbl, key, subkey, layoutOrd)
    local t = mkToggle(scroll, lbl, subkey and S[key][subkey] or S[key], 0, function(v)
        if subkey then S[key][subkey] = v else S[key] = v end
    end)
    t.LayoutOrder = layoutOrd or 0
end

-- секции
section("silent aim")
mkToggle(scroll,"silent aim",         S.Silent,      0, function(v) S.Silent=v end).LayoutOrder=1
mkToggle(scroll,"silent team check",  S.SilentTeam,  0, function(v) S.SilentTeam=v end).LayoutOrder=2
mkToggle(scroll,"silent wall check",  S.SilentWall,  0, function(v) S.SilentWall=v end).LayoutOrder=3

section("aimbot")
mkToggle(scroll,"aimbot",             S.Aimbot,      0, function(v) S.Aimbot=v end).LayoutOrder=5
mkToggle(scroll,"aim team check",     S.AimbotTeam,  0, function(v) S.AimbotTeam=v end).LayoutOrder=6
mkToggle(scroll,"aim wall check",     S.AimbotWall,  0, function(v) S.AimbotWall=v end).LayoutOrder=7

section("esp")
mkToggle(scroll,"esp",                S.ESP,         0, function(v) S.ESP=v end).LayoutOrder=9
mkToggle(scroll,"box",                S.ESPBox,      0, function(v) S.ESPBox=v end).LayoutOrder=10
mkToggle(scroll,"name",               S.ESPName,     0, function(v) S.ESPName=v end).LayoutOrder=11
mkToggle(scroll,"health",             S.ESPHealth,   0, function(v) S.ESPHealth=v end).LayoutOrder=12
mkToggle(scroll,"distance",           S.ESPDistance, 0, function(v) S.ESPDistance=v end).LayoutOrder=13
mkToggle(scroll,"tracer",             S.ESPTracer,   0, function(v) S.ESPTracer=v end).LayoutOrder=14
mkToggle(scroll,"team check",         S.ESPTeam,     0, function(v) S.ESPTeam=v end).LayoutOrder=15

-- авторасчёт высоты canvas
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end)
