-- Baldi Frenzy utility
-- Rayfield UI, client side

local Rayfield
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if not ok or not res then
        warn("rayfield load failed")
        return
    end
    Rayfield = res
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer
local char, hrp, hum
local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local espRate = mobile and 0.25 or 0.08

-- состояние
local flags = {
    stamina = false,
    speed = 16,
    noclip = false,
    esp = false,
    baldiClr = Color3.fromRGB(255, 50, 50),
    studentClr = Color3.fromRGB(0, 255, 120),
    bright = false,
    autoNotebook = false,
    hear = false,
    noDecay = false,
    isBaldi = false,
    tracers = false,
    boxEsp = false,
}

-- оригиналы для восстановления
local originals = {
    ambient = Lighting.Ambient,
    outdoor = Lighting.OutdoorAmbient,
    brightness = Lighting.Brightness,
    fogEnd = Lighting.FogEnd,
    clockTime = Lighting.ClockTime,
}

-- кэш ролей
local roleCache = {}
local ROLE_TTL = 1

local function isBaldi(m)
    if not m then return false end
    local cached = roleCache[m]
    if cached and os.clock() - cached.t < ROLE_TTL then
        return cached.v
    end

    local v = false
    local attr = m:GetAttribute("Role")
    if typeof(attr) == "string" and attr:lower() == "baldi" then
        v = true
    elseif m.Name:lower() == "baldi" then
        v = true
    else
        local p = Players:GetPlayerFromCharacter(m)
        if p and p.Team and p.Team.Name:lower():find("baldi", 1, true) then
            v = true
        elseif m:FindFirstChild("Ruler") or m:FindFirstChild("BaldiRuler") then
            v = true
        end
    end

    roleCache[m] = { v = v, t = os.clock() }
    return v
end

local function refreshRole()
    flags.isBaldi = isBaldi(char)
end

-- хуки
local bypass = {
    hooked = false,
    origCollide = {},
    fakeSpeed = 16,
}

function bypass.install()
    if bypass.hooked then return end
    if not hookmetamethod or not newcclosure or not checkcaller then
        return
    end

    local ok = pcall(function()
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if not checkcaller() then
                if key == "WalkSpeed" and self:IsA("Humanoid") then
                    return bypass.fakeSpeed
                end
                if key == "CanCollide" and self:IsA("BasePart") then
                    local orig = bypass.origCollide[self]
                    if orig ~= nil then
                        return orig
                    end
                end
            end
            return oldIndex(self, key)
        end))

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            return oldNamecall(self, ...)
        end))
    end)

    if ok then
        bypass.hooked = true
    end
end

function bypass.setSpeed(h, spd)
    if not h then return end
    bypass.fakeSpeed = 16
    pcall(function()
        h.WalkSpeed = spd
    end)
end

function bypass.teleport(root, pos)
    if not root or not pos then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    local jitter = Vector3.new(
        math.random() * 2 - 1,
        0,
        math.random() * 2 - 1
    ) * 1.5
    pcall(function()
        root.CFrame = CFrame.new(pos + jitter) * (root.CFrame - root.CFrame.Position)
    end)
end

function bypass.setNoclip(m, on)
    if not m or not m.Parent then return end
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then
            if on then
                if bypass.origCollide[p] == nil then
                    bypass.origCollide[p] = p.CanCollide
                end
                pcall(function()
                    p.CanCollide = false
                end)
            else
                local orig = bypass.origCollide[p]
                pcall(function()
                    p.CanCollide = orig == nil and true or orig
                end)
                bypass.origCollide[p] = nil
            end
        end
    end
end

bypass.install()

-- ESP
local espTags = {}
local espTracers = {}
local espBoxes = {}
local espConn
local lastEsp = 0

local function makeTag(part, text, color)
    if not part or espTags[part] then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "BF_ESP"
    bb.Size = UDim2.new(0, 120, 0, 32)
    bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.Parent = part

    local l = Instance.new("TextLabel")
    l.Name = "Label"
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color
    l.TextStrokeTransparency = 0.5
    l.TextScaled = true
    l.Font = Enum.Font.SourceSansBold
    l.Parent = bb

    espTags[part] = bb
end

local function makeTracer(part, color)
    if not part or espTracers[part] then return end
    local line = Drawing.new("Line")
    line.Thickness = 1
    line.Color = color
    line.Transparency = 1
    line.Visible = false
    espTracers[part] = line
end

local function makeBox(part)
    if not part or espBoxes[part] then return end
    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Color = Color3.fromRGB(255, 255, 255)
    box.Filled = false
    box.Visible = false
    espBoxes[part] = box
end

local function dropTag(part)
    local bb = espTags[part]
    if bb then
        pcall(function() bb:Destroy() end)
        espTags[part] = nil
    end
    local tr = espTracers[part]
    if tr then
        pcall(function() tr:Remove() end)
        espTracers[part] = nil
    end
    local bx = espBoxes[part]
    if bx then
        pcall(function() bx:Remove() end)
        espBoxes[part] = nil
    end
end

local function dropAll()
    for p in pairs(espTags) do dropTag(p) end
    for p in pairs(espTracers) do dropTag(p) end
    for p in pairs(espBoxes) do dropTag(p) end
end

local function repaint()
    for _, bb in pairs(espTags) do
        if bb.Parent then
            local l = bb:FindFirstChild("Label")
            if l then
                local b = l.Text == "BALDI"
                l.TextColor3 = b and flags.baldiClr or flags.studentClr
            end
        end
    end
    for _, line in pairs(espTracers) do
        local part
        for p, l in pairs(espTracers) do
            if l == line then part = p; break end
        end
        if part and part.Parent then
            local m = part:FindFirstAncestorOfClass("Model")
            line.Color = (m and isBaldi(m)) and flags.baldiClr or flags.studentClr
        end
    end
end

local function espTick()
    local now = os.clock()
    if now - lastEsp < espRate then return end
    lastEsp = now

    local seen = {}
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local screenSize = cam.ViewportSize

    for _, m in ipairs(Workspace:GetChildren()) do
        if m ~= char and m:IsA("Model") then
            local h = m:FindFirstChildOfClass("Humanoid")
            local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChild("Head")

            if h and root and root:IsA("BasePart") and h.Health > 0 then
                local pos, onScreen = cam:WorldToViewportPoint(root.Position)
                local b = isBaldi(m)
                local clr = b and flags.baldiClr or flags.studentClr
                local txt = b and "BALDI" or m.Name

                if onScreen then
                    local tag = espTags[root]
                    if tag and tag.Parent then
                        local l = tag:FindFirstChild("Label")
                        if l then
                            if l.Text ~= txt then l.Text = txt end
                            if l.TextColor3 ~= clr then l.TextColor3 = clr end
                        end
                    else
                        makeTag(root, txt, clr)
                    end
                elseif espTags[root] then
                    dropTag(root)
                end

                if flags.tracers then
                    local line = espTracers[root]
                    if not line then
                        makeTracer(root, clr)
                        line = espTracers[root]
                    end
                    if line then
                        if onScreen then
                            line.From = Vector2.new(screenSize.X / 2, screenSize.Y)
                            line.To = Vector2.new(pos.X, pos.Y)
                            line.Color = clr
                            line.Visible = true
                        else
                            line.Visible = false
                        end
                    end
                elseif espTracers[root] then
                    local line = espTracers[root]
                    pcall(function() line:Remove() end)
                    espTracers[root] = nil
                end

                if flags.boxEsp then
                    local box = espBoxes[root]
                    if not box then
                        makeBox(root)
                        box = espBoxes[root]
                    end
                    if box then
                        if onScreen then
                            local head = m:FindFirstChild("Head")
                            if head then
                                local headPos = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 1, 0))
                                local height = math.abs(headPos.Y - pos.Y) * 2
                                box.Size = Vector2.new(height / 2, height)
                                box.Position = Vector2.new(pos.X - height / 4, pos.Y - height / 2)
                                box.Color = clr
                                box.Visible = true
                            else
                                box.Visible = false
                            end
                        else
                            box.Visible = false
                        end
                    end
                elseif espBoxes[root] then
                    local box = espBoxes[root]
                    pcall(function() box:Remove() end)
                    espBoxes[root] = nil
                end

                seen[root] = true
            end
        end
    end

    for p in pairs(espTags) do
        if not seen[p] or not p.Parent then dropTag(p) end
    end
    for p in pairs(espTracers) do
        if not seen[p] or not p.Parent then dropTag(p) end
    end
    for p in pairs(espBoxes) do
        if not seen[p] or not p.Parent then dropTag(p) end
    end
end

local function toggleEsp()
    if flags.esp then
        if not espConn then
            espConn = RunService.Heartbeat:Connect(function()
                local ok, err = pcall(espTick)
                if not ok then warn("esp tick", err) end
            end)
        end
    else
        if espConn then
            espConn:Disconnect()
            espConn = nil
        end
        dropAll()
    end
end

-- noclip
local noclipConn
local function setNoclip(on)
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if on then
        noclipConn = RunService.Stepped:Connect(function()
            if char and char.Parent then
                bypass.setNoclip(char, true)
            end
        end)
    elseif char then
        bypass.setNoclip(char, false)
    end
end

-- инфинити стамина (оптимизированная)
local staminaConn
local function setStamina(on)
    if staminaConn then
        staminaConn:Disconnect()
        staminaConn = nil
    end
    if on then
        staminaConn = RunService.Heartbeat:Connect(function()
            if not char or not char.Parent then return end
            local gui = lp:FindFirstChild("PlayerGui")
            if not gui then return end
            for _, d in ipairs(gui:GetDescendants()) do
                if d:IsA("Frame") and d.Name:lower():find("stamina", 1, true) then
                    local f = d:FindFirstChild("Fill")
                    if f and f:IsA("GuiObject") and f.Size.X.Scale < 1 then
                        f.Size = UDim2.new(1, 0, 1, 0)
                    end
                end
            end
        end)
    end
end

-- привязка персонажа
local function bindChar()
    char = lp.Character
    if not char then return end
    hrp = char:WaitForChild("HumanoidRootPart", 5)
    hum = char:WaitForChild("Humanoid", 5)
    if hum then
        bypass.setSpeed(hum, flags.speed)
    end
end

lp.CharacterAdded:Connect(function()
    bindChar()
    task.wait(1)
    refreshRole()
    if flags.noclip then setNoclip(true) end
    if flags.stamina then setStamina(true) end
end)

lp.CharacterRemoving:Connect(function()
    if flags.noclip then bypass.origCollide = {} end
end)

bindChar()
refreshRole()

-- кэш поиска объектов
local cache = { notebook = {}, exit = {}, t = 0 }
local CACHE_TTL = 1.5

local function findTagged(kind, keys)
    local now = os.clock()
    if now - cache.t < CACHE_TTL and #cache[kind] > 0 then
        local out = {}
        for _, o in ipairs(cache[kind]) do
            if o.Parent then table.insert(out, o) end
        end
        if #out > 0 then return out end
    end

    local list = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("BasePart") then
            local n = o.Name:lower()
            for _, k in ipairs(keys) do
                if n:find(k, 1, true) then
                    table.insert(list, o)
                    break
                end
            end
        end
    end
    cache[kind] = list
    cache.t = now
    return list
end

local nbKeys = { "notebook" }
local exitKeys = { "exit" }
local tpCd = 0

local function tpTo(kind, keys, offset)
    if not hrp or not hrp.Parent then return "no char" end
    if os.clock() - tpCd < 0.6 then return "wait" end
    tpCd = os.clock()

    local best, dist = nil, math.huge
    for _, o in ipairs(findTagged(kind, keys)) do
        if o.Parent and (o.Transparency < 1 or kind == "exit") then
            local d = (o.Position - hrp.Position).Magnitude
            if d < dist then
                dist = d
                best = o
            end
        end
    end

    if best then
        bypass.teleport(hrp, best.Position + offset)
        return "done"
    end
    return "none found"
end

-- Baldi-only функции
local function setHearing(on)
    if not on then return end
    if not flags.isBaldi then return end
    local gui = lp:FindFirstChild("PlayerGui")
    if not gui then return end
    for _, d in ipairs(gui:GetDescendants()) do
        if (d:IsA("NumberValue") or d:IsA("IntValue")) and d.Name:lower():find("hearing", 1, true) then
            d.Value = 999
        end
    end
end

local hearConn
local function startHearing(always)
    if hearConn then
        hearConn:Disconnect()
        hearConn = nil
    end
    if not always then return end
    hearConn = RunService.Heartbeat:Connect(function()
        if not flags.isBaldi then return end
        if flags.hear or flags.noDecay then
            setHearing(true)
        end
    end)
end

-- UI
local win = Rayfield:CreateWindow({
    Name = "Baldi Frenzy Menu",
    LoadingTitle = "Baldi Frenzy Menu",
    LoadingSubtitle = "utility",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "BaldiFrenzy",
        FileName = "cfg",
    },
    KeySystem = false,
    ToggleUIKeybind = mobile and nil or "RightShift",
})

local main = win:CreateTab("Main", 4483362458)
main:CreateSection("Movement")

main:CreateToggle({
    Name = "Infinite Stamina",
    CurrentValue = false,
    Flag = "Stamina",
    Callback = function(v)
        flags.stamina = v
        setStamina(v)
    end,
})

main:CreateSlider({
    Name = "WalkSpeed",
    Range = { 16, 120 },
    Increment = mobile and 1 or 2,
    Suffix = " studs/s",
    CurrentValue = 16,
    Flag = "Speed",
    Callback = function(v)
        flags.speed = v
        if hum and hum.Parent then
            bypass.setSpeed(hum, v)
        end
    end,
})

main:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(v)
        flags.noclip = v
        setNoclip(v)
    end,
})

main:CreateSection("ESP")

main:CreateToggle({
    Name = "Player ESP",
    CurrentValue = false,
    Flag = "Esp",
    Callback = function(v)
        flags.esp = v
        toggleEsp()
    end,
})

main:CreateToggle({
    Name = "Tracers",
    CurrentValue = false,
    Flag = "Tracers",
    Callback = function(v)
        flags.tracers = v
    end,
})

main:CreateToggle({
    Name = "Box ESP",
    CurrentValue = false,
    Flag = "BoxEsp",
    Callback = function(v)
        flags.boxEsp = v
    end,
})

main:CreateColorPicker({
    Name = "Baldi Color",
    Color = flags.baldiClr,
    Flag = "BaldiClr",
    Callback = function(c)
        flags.baldiClr = c
        repaint()
    end,
})

main:CreateColorPicker({
    Name = "Student Color",
    Color = flags.studentClr,
    Flag = "StudentClr",
    Callback = function(c)
        flags.studentClr = c
        repaint()
    end,
})

main:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false,
    Flag = "Bright",
    Callback = function(v)
        flags.bright = v
        if v then
            originals.ambient = Lighting.Ambient
            originals.outdoor = Lighting.OutdoorAmbient
            originals.brightness = Lighting.Brightness
            originals.fogEnd = Lighting.FogEnd
            originals.clockTime = Lighting.ClockTime
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            Lighting.Brightness = 3
            Lighting.FogEnd = 10000
            Lighting.ClockTime = 12
        else
            Lighting.Ambient = originals.ambient
            Lighting.OutdoorAmbient = originals.outdoor
            Lighting.Brightness = originals.brightness
            Lighting.FogEnd = originals.fogEnd
            Lighting.ClockTime = originals.clockTime
        end
    end,
})

main:CreateButton({
    Name = "Clear ESP",
    Callback = function()
        flags.esp = false
        toggleEsp()
    end,
})

local stu = win:CreateTab("Student", 4483362458)

stu:CreateButton({
    Name = "TP to Notebook",
    Callback = function()
        Rayfield:Notify({
            Title = "Teleport",
            Content = tpTo("notebook", nbKeys, Vector3.new(0, 5, 0)),
            Duration = 2,
        })
    end,
})

stu:CreateButton({
    Name = "TP to Exit",
    Callback = function()
        Rayfield:Notify({
            Title = "Teleport",
            Content = tpTo("exit", exitKeys, Vector3.new(0, 5, 0)),
            Duration = 2,
        })
    end,
})

stu:CreateToggle({
    Name = "Auto Notebook",
    CurrentValue = false,
    Flag = "AutoNb",
    Callback = function(v)
        flags.autoNotebook = v
        if not v then return end
        task.spawn(function()
            while flags.autoNotebook do
                task.wait(mobile and 0.8 or 0.5)
                if not hrp or not hrp.Parent then continue end
                if not firetouchinterest then continue end
                for _, o in ipairs(findTagged("notebook", nbKeys)) do
                    if o.Parent and o.CanCollide and o.Transparency < 1 then
                        if (o.Position - hrp.Position).Magnitude < 50 then
                            pcall(firetouchinterest, hrp, o, 0)
                            task.wait(0.05)
                            pcall(firetouchinterest, hrp, o, 1)
                            task.wait(0.05)
                        end
                    end
                end
            end
        end)
    end,
})

stu:CreateButton({
    Name = "Collect All (local)",
    Callback = function()
        if not hrp or not hrp.Parent then
            Rayfield:Notify({ Title = "Collect", Content = "no char", Duration = 2 })
            return
        end
        if not firetouchinterest then
            Rayfield:Notify({ Title = "Collect", Content = "not supported", Duration = 2 })
            return
        end
        local count = 0
        for _, o in ipairs(findTagged("notebook", nbKeys)) do
            if o.Parent and o.CanCollide and o.Transparency < 1 then
                pcall(firetouchinterest, hrp, o, 0)
                task.wait(0.03)
                pcall(firetouchinterest, hrp, o, 1)
                task.wait(0.03)
                count += 1
            end
        end
        Rayfield:Notify({ Title = "Collect", Content = tostring(count) .. " done", Duration = 2 })
    end,
})

local bt = win:CreateTab("Baldi", 4483362458)

bt:CreateToggle({
    Name = "Always Hear",
    CurrentValue = false,
    Flag = "Hear",
    Callback = function(v)
        flags.hear = v
        if v and not flags.isBaldi then
            Rayfield:Notify({ Title = "Always Hear", Content = "role bald only", Duration = 3 })
            return
        end
        if v then startHearing(true) end
    end,
})

bt:CreateToggle({
    Name = "No Hearing Decay",
    CurrentValue = false,
    Flag = "NoDecay",
    Callback = function(v)
        flags.noDecay = v
        if v and not flags.isBaldi then
            Rayfield:Notify({ Title = "No Hearing Decay", Content = "role bald only", Duration = 3 })
            return
        end
        if v then startHearing(true) end
    end,
})

-- очистка
game:BindToClose(function()
    if espConn then espConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if staminaConn then staminaConn:Disconnect() end
    if hearConn then hearConn:Disconnect() end
    dropAll()
end)

Rayfield:Notify({
    Title = "Baldi Frenzy Menu",
    Content = mobile and "tap the floating button" or "RightShift to open",
    Duration = 4,
})
