-- ollie // harbor havoc v7 - mobile fix
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer
local MOB        = UserInput.TouchEnabled

local S = {
    Silent=true, SilentFOV=180, SilentPart="Head", SilentTeam=true, SilentWall=false,
    Aimbot=false, AimbotKey=Enum.KeyCode.E, AimbotFOV=180, AimbotSmooth=0.15,
    AimbotPart="Head", AimbotTeam=true, AimbotWall=false,
    ESP=true, ESPBox=true, ESPName=true, ESPHealth=true, ESPDistance=true,
    ESPTracer=false, ESPTeam=true, ESPMaxDist=2000,
}

local function getChar(p) return p and p.Character end
local function getRoot(p) local c=getChar(p); return c and c:FindFirstChild("HumanoidRootPart") end
local function getPart(p,n) local c=getChar(p); return c and (c:FindFirstChild(n) or c:FindFirstChild("HumanoidRootPart")) end
local function getHum(p) local c=getChar(p); return c and c:FindFirstChildOfClass("Humanoid") end
local function isAlive(p) local h=getHum(p); return h and h.Health>0 end
local function sameTeam(p) return LP.Team and p.Team and LP.Team==p.Team end

local function wallCheck(pos, target)
    local origin = Camera.CFrame.Position
    local dir = pos - origin
    local ray = RaycastParams.new()
    local filter = {}
    local lc = getChar(LP); if lc then table.insert(filter, lc) end
    local tc = target and getChar(target); if tc then table.insert(filter, tc) end
    local folder = workspace:FindFirstChild("Folder"); if folder then table.insert(filter, folder) end
    ray.FilterDescendantsInstances = filter
    ray.FilterType = Enum.RaycastFilterType.Exclude
    return workspace:Raycast(origin, dir, ray) == nil
end

local function getFOVTarget(fov, part)
    local best, bestDist = nil, fov
    local c = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not (S.AimbotTeam and sameTeam(p)) then
            local bp = getPart(p, part)
            if bp then
                local pos, vis = Camera:WorldToViewportPoint(bp.Position)
                if vis then
                    local d = (Vector2.new(pos.X, pos.Y) - c).Magnitude
                    if d < bestDist then bestDist = d; best = p end
                end
            end
        end
    end
    return best
end

local function getSilentTarget(fov, part)
    local best, bestDist = nil, fov
    local c = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) and not (S.SilentTeam and sameTeam(p)) then
            local bp = getPart(p, part)
            if bp and (not S.SilentWall or wallCheck(bp.Position, p)) then
                local pos, vis = Camera:WorldToViewportPoint(bp.Position)
                if vis then
                    local d = (Vector2.new(pos.X, pos.Y) - c).Magnitude
                    if d < bestDist then bestDist = d; best = p end
                end
            end
        end
    end
    return best
end

-- silent aim: namecall only, hookfunction on FireServer doesn't work
local FireWeapon
pcall(function()
    local R = RS:WaitForChild("Remotes", 10)
    if R then FireWeapon = R:WaitForChild("FireWeapon", 10) end
end)

if FireWeapon then
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local oldNC = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        if S.Silent and self == FireWeapon and getnamecallmethod() == "FireServer" then
            local target = getSilentTarget(S.SilentFOV, S.SilentPart)
            if target then
                local bp = getPart(target, S.SilentPart)
                if bp then
                    local args = {...}
                    for i = 1, #args do
                        if typeof(args[i]) == "CFrame" then
                            args[i] = CFrame.new(bp.Position)
                        elseif typeof(args[i]) == "Vector3" then
                            args[i] = bp.Position
                        end
                    end
                    return oldNC(self, table.unpack(args))
                end
            end
        end
        return oldNC(self, ...)
    end)
    setreadonly(mt, true)
end

-- aimbot: on mobile ignore key requirement
RunService.RenderStepped:Connect(function()
    if not S.Aimbot then return end
    if not MOB and not UserInput:IsKeyDown(S.AimbotKey) then return end
    local target = getFOVTarget(S.AimbotFOV, S.AimbotPart)
    if not target then return end
    local bp = getPart(target, S.AimbotPart)
    if not bp then return end
    if S.AimbotWall and not wallCheck(bp.Position, target) then return end
    Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, bp.Position), S.AimbotSmooth)
end)

-- ESP
local espObjects = {}
local function removeESP(p)
    if espObjects[p] then
        for _, v in pairs(espObjects[p]) do pcall(function() v:Remove() end) end
        espObjects[p] = nil
    end
end
local function makeESP(p)
    removeESP(p)
    local t = {}
    local box = Drawing.new("Square"); box.Visible=false; box.Filled=false
    box.Color=Color3.fromRGB(255,60,60); box.Thickness=1; t.box = box
    local nm = Drawing.new("Text"); nm.Visible=false; nm.Center=true; nm.Outline=true
    nm.Size=13; nm.Color=Color3.fromRGB(255,255,255); t.name = nm
    local hbBg = Drawing.new("Square"); hbBg.Visible=false; hbBg.Filled=true
    hbBg.Color=Color3.fromRGB(0,0,0); hbBg.Thickness=1; t.hbBg = hbBg
    local hb = Drawing.new("Square"); hb.Visible=false; hb.Filled=true
    hb.Color=Color3.fromRGB(60,220,60); hb.Thickness=1; t.hb = hb
    local dt = Drawing.new("Text"); dt.Visible=false; dt.Center=true; dt.Outline=true
    dt.Size=11; dt.Color=Color3.fromRGB(220,220,220); t.dist = dt
    local tr = Drawing.new("Line"); tr.Visible=false; tr.Thickness=1
    tr.Color=Color3.fromRGB(255,60,60); t.tracer = tr
    espObjects[p] = t
end

local function updateESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            if not espObjects[p] then makeESP(p) end
            local t = espObjects[p]
            local vis = S.ESP and isAlive(p)
            if S.ESPTeam and sameTeam(p) then vis = false end
            if not vis then
                for _, v in pairs(t) do v.Visible = false end
            else
                local char, root, hum = getChar(p), getRoot(p), getHum(p)
                if not char or not root or not hum then
                    for _, v in pairs(t) do v.Visible = false end
                else
                    local rsp, on = Camera:WorldToViewportPoint(root.Position)
                    local dist3d = (root.Position - Camera.CFrame.Position).Magnitude
                    if not on or dist3d > S.ESPMaxDist then
                        for _, v in pairs(t) do v.Visible = false end
                    else
                        local head = char:FindFirstChild("Head")
                        local topP = head and Camera:WorldToViewportPoint(head.Position + Vector3.new(0,0.7,0)) or rsp
                        local botP = Camera:WorldToViewportPoint(root.Position - Vector3.new(0,2.8,0))
                        local top = Vector2.new(topP.X, topP.Y)
                        local bot = Vector2.new(botP.X, botP.Y)
                        local h = math.abs(bot.Y - top.Y)
                        local w = h * 0.5
                        local x = top.X - w/2
                        t.box.Visible = S.ESPBox
                        t.box.Position = Vector2.new(x, top.Y)
                        t.box.Size = Vector2.new(w, h)
                        t.name.Visible = S.ESPName
                        t.name.Position = Vector2.new(top.X, top.Y - 15)
                        t.name.Text = p.DisplayName
                        local hp = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
                        t.hbBg.Visible = S.ESPHealth
                        t.hbBg.Position = Vector2.new(x-6, top.Y)
                        t.hbBg.Size = Vector2.new(3, h)
                        t.hb.Visible = S.ESPHealth
                        t.hb.Position = Vector2.new(x-6, top.Y + h*(1-hp))
                        t.hb.Size = Vector2.new(3, h*hp)
                        t.hb.Color = Color3.fromRGB(math.floor((1-hp)*255), math.floor(hp*255), 0)
                        t.dist.Visible = S.ESPDistance
                        t.dist.Position = Vector2.new(top.X, bot.Y + 2)
                        t.dist.Text = math.floor(dist3d) .. "u"
                        t.tracer.Visible = S.ESPTracer
                        t.tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                        t.tracer.To = Vector2.new(rsp.X, rsp.Y)
                    end
                end
            end
        end
    end
end
Players.PlayerRemoving:Connect(removeESP)
RunService.RenderStepped:Connect(updateESP)

-- UI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ollie_hh"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = LP.PlayerGui end

local function mkFrame(parent, size, pos, color, radius)
    local f = Instance.new("Frame", parent)
    f.Size = size; f.Position = pos
    f.BackgroundColor3 = color or Color3.fromRGB(14,14,18)
    f.BorderSizePixel = 0
    if radius then Instance.new("UICorner", f).CornerRadius = UDim.new(0, radius) end
    return f
end
local function mkLabel(parent, text, size, color, pos)
    local l = Instance.new("TextLabel", parent)
    l.Size = size; l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = color or Color3.fromRGB(220,220,230)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    return l
end

local win = mkFrame(ScreenGui, UDim2.fromOffset(240, 460), UDim2.new(0,16,0.5,-230), Color3.fromRGB(14,14,18), 8)
local title = mkFrame(win, UDim2.new(1,0,0,30), UDim2.new(), Color3.fromRGB(10,10,14), 8)
mkLabel(title, "ollie // harbor havoc", UDim2.new(1,-72,1,0), Color3.fromRGB(180,180,200), UDim2.new(0,8,0,0))

local bs = 26
local minBtn = Instance.new("TextButton", title)
minBtn.Size = UDim2.fromOffset(bs,bs)
minBtn.Position = UDim2.new(1, -bs*2-4, 0, 2)
minBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
minBtn.Text = "-"; minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 16; minBtn.TextColor3 = Color3.fromRGB(220,220,230)
minBtn.AutoButtonColor = false
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local closeBtn = Instance.new("TextButton", title)
closeBtn.Size = UDim2.fromOffset(bs,bs)
closeBtn.Position = UDim2.new(1, -bs-2, 0, 2)
closeBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
closeBtn.Text = "x"; closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16; closeBtn.TextColor3 = Color3.fromRGB(220,220,230)
closeBtn.AutoButtonColor = false
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

local fab = Instance.new("TextButton", ScreenGui)
fab.Size = UDim2.fromOffset(48,48)
fab.Position = UDim2.new(1,-60,1,-60)
fab.BackgroundColor3 = Color3.fromRGB(80,200,120)
fab.Text = "O"; fab.Font = Enum.Font.GothamBold
fab.TextSize = 20; fab.TextColor3 = Color3.fromRGB(15,15,20)
fab.AutoButtonColor = false
fab.Visible = false
Instance.new("UICorner", fab).CornerRadius = UDim.new(0, 24)

-- drag with touch
local dragging, dragStart, startPos = false, nil, nil
title.InputBegan:Connect(function(i)
    if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
        local rel = i.Position - title.AbsolutePosition
        if rel.X > title.AbsoluteSize.X - 70 then return end
        dragging = true
        dragStart = i.Position
        startPos = win.Position
    end
end)
UserInput.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInput.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- scroll content
local scroll = Instance.new("ScrollingFrame", win)
scroll.Size = UDim2.new(1,0,1,-34)
scroll.Position = UDim2.new(0,0,0,32)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(80,80,100)
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local layout = Instance.new("UIListLayout", scroll)
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local order = 0
local function nextOrder() order = order + 1; return order end

local function section(name)
    local s = Instance.new("TextLabel", scroll)
    s.Size = UDim2.new(1,-16,0,18)
    s.BackgroundTransparency = 1
    s.Font = Enum.Font.GothamBold
    s.TextSize = 10
    s.TextColor3 = Color3.fromRGB(100,120,180)
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Text = "  " .. string.upper(name)
    s.LayoutOrder = nextOrder()
    return s
end

local function mkToggle(parent, lbl, state, onChange)
    local row = mkFrame(parent, UDim2.new(1,-16,0,28), UDim2.new(0,8,0,0), Color3.fromRGB(20,20,26), 4)
    row.LayoutOrder = nextOrder()
    mkLabel(row, lbl, UDim2.new(1,-52,1,0), nil, UDim2.new(0,8,0,0))
    local track = mkFrame(row, UDim2.fromOffset(36,18), UDim2.new(1,-44,0.5,-9),
        state and Color3.fromRGB(80,200,120) or Color3.fromRGB(60,60,70), 9)
    local knob = mkFrame(track, UDim2.fromOffset(14,14),
        UDim2.new(state and 1 or 0, state and -16 or 2, 0.5, -7),
        Color3.fromRGB(255,255,255), 7)
    local hit = Instance.new("TextButton", row)
    hit.Size = UDim2.fromScale(1,1)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    local on = state
    hit.MouseButton1Click:Connect(function()
        on = not on
        track.BackgroundColor3 = on and Color3.fromRGB(80,200,120) or Color3.fromRGB(60,60,70)
        knob:TweenPosition(UDim2.new(on and 1 or 0, on and -16 or 2, 0.5, -7),
            Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
        onChange(on)
    end)
    return row
end

section("silent aim")
mkToggle(scroll, "silent aim",        S.Silent,     function(v) S.Silent=v end)
mkToggle(scroll, "silent team check", S.SilentTeam, function(v) S.SilentTeam=v end)
mkToggle(scroll, "silent wall check", S.SilentWall, function(v) S.SilentWall=v end)
section("aimbot")
mkToggle(scroll, "aimbot",            S.Aimbot,     function(v) S.Aimbot=v end)
mkToggle(scroll, "aim team check",    S.AimbotTeam, function(v) S.AimbotTeam=v end)
mkToggle(scroll, "aim wall check",    S.AimbotWall, function(v) S.AimbotWall=v end)
section("esp")
mkToggle(scroll, "esp",               S.ESP,        function(v) S.ESP=v end)
mkToggle(scroll, "box",               S.ESPBox,     function(v) S.ESPBox=v end)
mkToggle(scroll, "name",              S.ESPName,    function(v) S.ESPName=v end)
mkToggle(scroll, "health",            S.ESPHealth,  function(v) S.ESPHealth=v end)
mkToggle(scroll, "distance",          S.ESPDistance,function(v) S.ESPDistance=v end)
mkToggle(scroll, "tracer",            S.ESPTracer,  function(v) S.ESPTracer=v end)
mkToggle(scroll, "team check",        S.ESPTeam,    function(v) S.ESPTeam=v end)

-- minimize / close
local collapsed = false
minBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    win:TweenSize(collapsed and UDim2.fromOffset(240,30) or UDim2.fromOffset(240,460),
        Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
    scroll.Visible = not collapsed
    minBtn.Text = collapsed and "+" or "-"
end)
closeBtn.MouseButton1Click:Connect(function()
    win.Visible = false
    fab.Visible = true
end)
fab.MouseButton1Click:Connect(function()
    fab.Visible = false
    win.Visible = true
    if collapsed then
        collapsed = false
        win.Size = UDim2.fromOffset(240,460)
        scroll.Visible = true
        minBtn.Text = "-"
    end
end)
