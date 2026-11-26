local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local WS           = game:GetService("Workspace")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local LocalPlayer  = Players.LocalPlayer
local Camera       = WS.CurrentCamera
local CONFIG_FILE    = "ant_hub_matcha.json"
local FALLBACK_CODES = {"ANTS", "EVOLVE", "RELEASE", "QUEEN"}
local RECORD_KEYS    = {"food","grow","evolve","rebirth","ants","bugs","boss","mutate","roll","pets","eggs","sugar","feast","play"}
local UPGRADE_LIST   = {"Jaws", "Magnet", "Shell", "Legs", "Appetite", "Regen"}
local PLAYTIME_SLOTS = 10
local QUEST_SLOTS    = 3
local CLAIM_GAP      = 1.15
if _G.ANT_HUB_STOP then
    pcall(_G.ANT_HUB_STOP, true)
end
local SCRIPT_ID = tick()
_G.ANT_HUB_BOOT = SCRIPT_ID
local function isAlive()
    return _G.ANT_HUB_BOOT == SCRIPT_ID
end
local Rem = RS:WaitForChild("AntRemotes", 10)
local function getRemote(name)
    return Rem and Rem:FindFirstChild(name)
end
local R = {
    Evolve         = getRemote("Evolve"),
    Rebirth        = getRemote("Rebirth"),
    BuyUpgrade     = getRemote("BuyUpgrade"),
    ClaimDaily     = getRemote("ClaimDaily"),
    ClaimPlaytime  = getRemote("ClaimPlaytime"),
    ClaimQuest     = getRemote("ClaimQuest"),
    ClaimRecord    = getRemote("ClaimRecord"),
    Redeem         = getRemote("Redeem"),
    CommunityClaim = getRemote("CommunityClaim"),
}
local function getHRP(char)
    local c = char or LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart or c:FindFirstChild("Head"))
end
local function invokeServerSafe(remoteInstance, ...)
    if not remoteInstance then return false end
    local args = {...}
    local ok, res = pcall(function()
        if remoteInstance.ClassName == "RemoteFunction" then
            return remoteInstance:InvokeServer(table.unpack(args))
        elseif remoteInstance.ClassName == "RemoteEvent" then
            remoteInstance:FireServer(table.unpack(args))
            return true
        end
    end)
    return ok and res
end
local function getJsonAttr(attrName)
    local raw = LocalPlayer:GetAttribute(attrName)
    if type(raw) ~= "string" then return nil end
    local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
    return (ok and type(res) == "table") and res or nil
end
local WIDGET_IDS = {
    "hitbox_on", "hitbox_reach", "hitbox_size",
    "hitbox_mobs", "hitbox_bosses", "hitbox_players", "hitbox_bots",
    "speed_on", "speed_val", "fly_on", "antidmg_on", "dodge_dist",
    "antiboss_aoe", "boss_dodge_dist", "keepaway_on", "keep_radius",
    "magnet_on", "magnet_val",
    "esp_on", "esp_box", "esp_name", "esp_hp", "esp_hp_text",
    "esp_dist", "esp_tracers", "esp_max_dist",
    "esp_mobs", "esp_bosses", "esp_players", "esp_bots",
    "auto_evo", "auto_rebirth", "auto_upg", "upg_idx", "rewards_auto"
}
local function saveConfig()
    local dump = {}
    for _, id in ipairs(WIDGET_IDS) do
        dump[id] = UI.GetValue(id)
    end
    writefile(CONFIG_FILE, HttpService:JSONEncode(dump))
    print("[AntHub] Config saved to " .. CONFIG_FILE)
end
local function loadConfig()
    if not isfile(CONFIG_FILE) then return end
    local ok, dump = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and type(dump) == "table" then
        for _, id in ipairs(WIDGET_IDS) do
            if dump[id] ~= nil then
                UI.SetValue(id, dump[id])
            end
        end
        print("[AntHub] Config loaded successfully.")
    end
end
local rewardsBusy = false
local seenRecords = {}
local function claimAllRewards(silent)
    if rewardsBusy then return end
    rewardsBusy = true
    local initialDNA = tonumber(LocalPlayer:GetAttribute("DNA")) or 0
    local function tryCall(remInst, arg)
        invokeServerSafe(remInst, arg)
        task.wait(CLAIM_GAP)
    end
    local dailyNext = tonumber(LocalPlayer:GetAttribute("DailyNext")) or 0
    if dailyNext <= os.time() then
        tryCall(R.ClaimDaily)
    end
    local claimedPlay = {}
    for _, v in ipairs(getJsonAttr("PlaytimeClaimed") or {}) do
        claimedPlay[tonumber(v) or 0] = true
    end
    for slot = 1, PLAYTIME_SLOTS do
        if not claimedPlay[slot] then
            tryCall(R.ClaimPlaytime, slot)
        end
    end
    local qData = getJsonAttr("Quests")
    local allDone = (qData ~= nil and type(qData.q) == "table")
    for slot = 1, QUEST_SLOTS do
        local row = qData and qData.q and qData.q[slot]
        local ready = not row or (tonumber(row[4]) or 0) >= (tonumber(row[3]) or 1)
        if row and row[5] ~= 1 and not ready then
            allDone = false
        end
        if not row or (row[5] ~= 1 and ready) then
            tryCall(R.ClaimQuest, slot)
        end
    end
    if not qData or (qData.b ~= 1 and allDone) then
        tryCall(R.ClaimQuest, "bonus")
    end
    local function getTier(idx)
        local rec = getJsonAttr("Records")
        local row = rec and rec[idx]
        return row and tonumber(row[1]) or 0, row and tonumber(row[2]) or 0
    end
    for idx, key in ipairs(RECORD_KEYS) do
        local tier, prog = getTier(idx)
        if seenRecords[key] ~= prog or not silent then
            for _ = 1, 5 do
                tryCall(R.ClaimRecord, key)
                local t2 = getTier(idx)
                if t2 <= tier then break end
                tier = t2
            end
            seenRecords[key] = prog
        end
    end
    if LocalPlayer:GetAttribute("CommunityClaimed") ~= true then
        tryCall(R.CommunityClaim)
    end
    rewardsBusy = false
    local gain = (tonumber(LocalPlayer:GetAttribute("DNA")) or 0) - initialDNA
    print(string.format("[Rewards] Claim complete. DNA: +%d", gain))
end
local function redeemAllCodes()
    local codes = {}
    local ok, src = pcall(function() return decompile(RS.Ant.Config) end)
    if ok and type(src) == "string" then
        local a = string.find(src, "%.Codes = {")
        local b = a and string.find(src, "%.Community = {", a)
        if a and b then
            for code in string.gmatch(string.sub(src, a, b), '%["([%u%d_]+)"%]') do
                codes[#codes + 1] = code
            end
        end
    end
    if #codes == 0 then codes = FALLBACK_CODES end
    local initialDNA = tonumber(LocalPlayer:GetAttribute("DNA")) or 0
    for _, code in ipairs(codes) do
        invokeServerSafe(R.Redeem, code)
        task.wait(CLAIM_GAP)
    end
    local gain = (tonumber(LocalPlayer:GetAttribute("DNA")) or 0) - initialDNA
    print(string.format("[Codes] %d codes redeemed. DNA: +%d", #codes, gain))
end
local activeTargets = {}
local targetThreats = {}
task.spawn(function()
    while isAlive() do
        local targets, threats = {}, {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local root = getHRP(p.Character)
                if root then
                    threats[#threats + 1] = root
                    local hp = tonumber(p.Character:GetAttribute("HP") or 0) or 0
                    local maxHp = tonumber(p.Character:GetAttribute("MaxHP") or 60) or 60
                    targets[#targets + 1] = {
                        instance = p.Character,
                        root     = root,
                        name     = p.Name,
                        stage    = tostring(p:GetAttribute("Stage") or "?"),
                        hp       = hp,
                        maxHp    = math.max(maxHp, 1),
                        category = "Player",
                        tagLabel = "PLAYER",
                        color    = Color3.fromRGB(0, 220, 255)
                    }
                end
            end
        end
        local ants = WS:FindFirstChild("Ants")
        if ants then
            local critters = ants:FindFirstChild("Critters")
            if critters then
                for _, c in ipairs(critters:GetChildren()) do
                    local root = getHRP(c)
                    if root then
                        threats[#threats + 1] = root
                        local hp = tonumber(c:GetAttribute("HP") or 0) or 0
                        local maxHp = tonumber(c:GetAttribute("MaxHP") or hp or 100) or 100
                        local isBoss = hp >= 5000 or c.Name:lower():find("queen") ~= nil or c.Name:lower():find("boss") ~= nil
                        targets[#targets + 1] = {
                            instance = c,
                            root     = root,
                            name     = c.Name,
                            stage    = isBoss and "BOSS" or "MOB",
                            hp       = hp,
                            maxHp    = math.max(maxHp, 1),
                            category = isBoss and "Boss" or "Mob",
                            tagLabel = isBoss and "BOSS" or "MOB",
                            color    = isBoss and Color3.fromRGB(255, 35, 35) or Color3.fromRGB(50, 255, 100)
                        }
                    end
                end
            end
            local bots = ants:FindFirstChild("Bots")
            if bots then
                for _, b in ipairs(bots:GetChildren()) do
                    local root = getHRP(b)
                    if root then
                        threats[#threats + 1] = root
                        local hp = tonumber(b:GetAttribute("HP") or 0) or 0
                        local maxHp = tonumber(b:GetAttribute("MaxHP") or hp or 100) or 100
                        local isBoss = hp >= 5000 or b:GetAttribute("IsBoss") == true
                        targets[#targets + 1] = {
                            instance = b,
                            root     = root,
                            name     = b.Name,
                            stage    = isBoss and "ELITE" or "BOT",
                            hp       = hp,
                            maxHp    = math.max(maxHp, 1),
                            category = isBoss and "Boss" or "Bot",
                            tagLabel = isBoss and "BOSS" or "BOT",
                            color    = isBoss and Color3.fromRGB(255, 35, 35) or Color3.fromRGB(255, 195, 0)
                        }
                    end
                end
            end
        end
        activeTargets = targets
        targetThreats = threats
        task.wait(0.3)
    end
end)
local origCharLength = nil
task.spawn(function()
    while isAlive() do
        local enabled = UI.GetValue("hitbox_on")
        local reachVal = UI.GetValue("hitbox_reach") or 80
        local partSize = UI.GetValue("hitbox_size") or 14
        local doMobs = UI.GetValue("hitbox_mobs")
        local doBosses = UI.GetValue("hitbox_bosses")
        local doPlayers = UI.GetValue("hitbox_players")
        local doBots = UI.GetValue("hitbox_bots")
        local myChar = LocalPlayer.Character
        if enabled then
            if myChar then
                if not origCharLength then
                    origCharLength = myChar:GetAttribute("Length") or 10
                end
                if myChar:GetAttribute("Length") ~= reachVal then
                    pcall(function() myChar:SetAttribute("Length", reachVal) end)
                end
            end
            local list = table.clone(activeTargets)
            for _, t in ipairs(list) do
                if t and t.root and t.root.Parent then
                    local allowed = false
                    if t.category == "Mob" and doMobs then allowed = true
                    elseif t.category == "Boss" and doBosses then allowed = true
                    elseif t.category == "Player" and doPlayers then allowed = true
                    elseif t.category == "Bot" and doBots then allowed = true
                    end
                    if allowed then
                        if math.abs(t.root.Size.X - partSize) > 0.5 then
                            pcall(function()
                                t.root.Size = Vector3.new(partSize, partSize, partSize)
                                t.root.CanCollide = false
                            end)
                        end
                        if t.instance and t.category == "Mob" and t.instance:GetAttribute("Length") ~= reachVal then
                            pcall(function() t.instance:SetAttribute("Length", reachVal) end)
                        end
                    end
                end
            end
        else
            if origCharLength and myChar then
                pcall(function() myChar:SetAttribute("Length", origCharLength) end)
                origCharLength = nil
            end
        end
        task.wait(0.4)
    end
end)
local prevHP = nil
local lastGeneralDodge = 0
local lastBossDodge = 0
local function checkBossTelegraphs()
    local myChar = LocalPlayer.Character
    local myHRP = getHRP(myChar)
    if not myChar or not myHRP then return end
    local myPos = myHRP.Position
    local dodgeDist = UI.GetValue("boss_dodge_dist") or 35
    local dangerFound, dangerCenter = false, nil
    local cfx = WS:FindFirstChild("ClientFx")
    if cfx then
        for _, fx in ipairs(cfx:GetChildren()) do
            local fn = fx.Name:lower()
            if fn:find("aim") or fn:find("anteater") or fn:find("telegraph") or fn:find("flash") or fn:find("area") or fn:find("boss") then
                local p = (fx.ClassName == "Part" or fx.ClassName == "MeshPart") and fx.Position
                if p then
                    local d = (p - myPos).Magnitude
                    local dangerRadius = 26
                    if fx.ClassName == "Part" and fx.Size.X > 5 then
                        dangerRadius = math.max(fx.Size.X * 0.65, 20)
                    end
                    if d <= dangerRadius then
                        dangerFound = true
                        dangerCenter = p
                        break
                    end
                end
            end
        end
    end
    if dangerFound and dangerCenter and (tick() - lastBossDodge) > 0.5 then
        local dx = myPos.X - dangerCenter.X
        local dz = myPos.Z - dangerCenter.Z
        local mag = math.sqrt(dx * dx + dz * dz)
        if mag < 0.01 then
            local look = myHRP.CFrame.LookVector
            dx, dz, mag = -look.X, -look.Z, 1
        end
        local factor = dodgeDist / mag
        pcall(function()
            myHRP.CFrame = CFrame.new(myPos.X + dx * factor, myPos.Y + 2, myPos.Z + dz * factor)
        end)
        lastBossDodge = tick()
    end
end
local function runDefense()
    local antiDmg = UI.GetValue("antidmg_on")
    local keepAway = UI.GetValue("keepaway_on")
    local antiBoss = UI.GetValue("antiboss_aoe")
    if antiBoss then
        checkBossTelegraphs()
    end
    if not (antiDmg or keepAway) then
        prevHP = nil
        return
    end
    local myChar = LocalPlayer.Character
    local myHRP = getHRP(myChar)
    if not myChar or not myHRP then return end
    local currentHP = tonumber(myChar:GetAttribute("HP")) or 0
    local wasHit = prevHP ~= nil and currentHP < (prevHP - 0.5)
    prevHP = currentHP
    if (tick() - lastGeneralDodge) < 1.1 then return end
    local myPos = myHRP.Position
    local nearestPos, nearestDist = nil, math.huge
    for _, root in ipairs(targetThreats) do
        local ok, pos = pcall(function() return root.Position end)
        if ok and pos then
            local d = (pos - myPos).Magnitude
            if d < nearestDist and d < 400 then
                nearestDist = d
                nearestPos = pos
            end
        end
    end
    local dodgeDist = UI.GetValue("dodge_dist") or 25
    local keepRadius = UI.GetValue("keep_radius") or 18
    local shouldDodge = false
    local fromPos = nil
    if antiDmg and wasHit then
        shouldDodge = true
        fromPos = (nearestPos and nearestDist < 60) and nearestPos or nil
    elseif keepAway and nearestPos and nearestDist < keepRadius then
        shouldDodge = true
        fromPos = nearestPos
    end
    if shouldDodge then
        local dx, dz
        if fromPos then
            dx = myPos.X - fromPos.X
            dz = myPos.Z - fromPos.Z
        else
            local look = myHRP.CFrame.LookVector
            dx, dz = -look.X, -look.Z
        end
        local mag = math.sqrt(dx * dx + dz * dz)
        if mag < 0.01 then dx, dz, mag = 1, 0, 1 end
        local factor = dodgeDist / mag
        pcall(function()
            myHRP.CFrame = CFrame.new(myPos.X + dx * factor, myPos.Y + 1.5, myPos.Z + dz * factor)
        end)
        lastGeneralDodge = tick()
    end
end
task.spawn(function()
    while isAlive() do
        pcall(runDefense)
        task.wait(0.06)
    end
end)
local magnetActive = false
task.spawn(function()
    while isAlive() do
        local autoOrb = UI.GetValue("magnet_on")
        local magnetVal = UI.GetValue("magnet_val") or 500
        if autoOrb then
            if not magnetActive or LocalPlayer:GetAttribute("MagnetMult") ~= magnetVal then
                pcall(function() LocalPlayer:SetAttribute("MagnetMult", magnetVal) end)
                magnetActive = true
            end
        elseif magnetActive then
            pcall(function() LocalPlayer:SetAttribute("MagnetMult", 1) end)
            magnetActive = false
        end
        task.wait(0.2)
    end
end)
task.spawn(function()
    while isAlive() do
        local fly = UI.GetValue("fly_on")
        local speed = UI.GetValue("speed_on")
        local speedVal = UI.GetValue("speed_val") or 60
        if fly or speed then
            local hrp = getHRP()
            if hrp then
                local ok, vel = pcall(function() return hrp.AssemblyLinearVelocity end)
                if ok and vel then
                    local vx, vy, vz = vel.X, vel.Y, vel.Z
                    local update = false
                    if speed then
                        local lv = hrp.CFrame.LookVector
                        vx, vz = lv.X * speedVal, lv.Z * speedVal
                        update = true
                    end
                    if fly and vy < 6 then
                        vy = 26
                        update = true
                    end
                    if update then
                        pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz) end)
                    end
                end
            end
        end
        task.wait(0.05)
    end
end)
local lastTimers = {evo = 0, reb = 0, upg = 0, red = 0}
task.spawn(function()
    while isAlive() do
        local now = tick()
        if UI.GetValue("auto_evo") and (now - lastTimers.evo) >= 1 then
            local pwr = tonumber(LocalPlayer:GetAttribute("Power"))
            local req = tonumber(LocalPlayer:GetAttribute("Need"))
            if pwr and req and pwr >= req then
                lastTimers.evo = now
                invokeServerSafe(R.Evolve)
            end
        end
        if UI.GetValue("auto_rebirth") and (now - lastTimers.reb) >= 10 then
            lastTimers.reb = now
            invokeServerSafe(R.Rebirth)
        end
        if UI.GetValue("auto_upg") and (now - lastTimers.upg) >= 5 then
            lastTimers.upg = now
            local idx = UI.GetValue("upg_idx") or 0
            local targetName = UPGRADE_LIST[idx + 1] or "Jaws"
            invokeServerSafe(R.BuyUpgrade, targetName)
        end
        if UI.GetValue("rewards_auto") and (now - lastTimers.red) >= 60 then
            lastTimers.red = now
            task.spawn(function() claimAllRewards(true) end)
        end
        task.wait(0.5)
    end
end)
local MAX_ESP_POOL = 30
local espPool = {}
for i = 1, MAX_ESP_POOL do
    local box = Drawing.new("Square")
    box.Thickness = 1.5
    box.Filled = false
    box.Visible = false
    local barBg = Drawing.new("Square")
    barBg.Filled = true
    barBg.Color = Color3.fromRGB(15, 15, 15)
    barBg.Visible = false
    local bar = Drawing.new("Square")
    bar.Filled = true
    bar.Visible = false
    local nameTag = Drawing.new("Text")
    nameTag.Size = 13
    nameTag.Center = true
    nameTag.Outline = true
    nameTag.Font = 1
    nameTag.Visible = false
    local subTag = Drawing.new("Text")
    subTag.Size = 11
    subTag.Center = true
    subTag.Outline = true
    subTag.Font = 1
    subTag.Visible = false
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Visible = false
    espPool[i] = {
        box = box,
        barBg = barBg,
        bar = bar,
        nameTag = nameTag,
        subTag = subTag,
        tracer = tracer
    }
end
local function hideESP(item)
    if not item then return end
    item.box.Visible = false
    item.barBg.Visible = false
    item.bar.Visible = false
    item.nameTag.Visible = false
    item.subTag.Visible = false
    item.tracer.Visible = false
end
local activeEspCount = 0
local espConnection = RunService.RenderStepped:Connect(function()
    local renderCount = 0
    local espEnabled = UI.GetValue("esp_on")
    local drawBox = UI.GetValue("esp_box")
    local showNames = UI.GetValue("esp_name")
    local showHpBar = UI.GetValue("esp_hp")
    local showHpText = UI.GetValue("esp_hp_text")
    local showDist = UI.GetValue("esp_dist")
    local drawTracers = UI.GetValue("esp_tracers")
    local maxDist = UI.GetValue("esp_max_dist") or 1000
    local showMobs = UI.GetValue("esp_mobs")
    local showBosses = UI.GetValue("esp_bosses")
    local showPlayers = UI.GetValue("esp_players")
    local showBots = UI.GetValue("esp_bots")
    if espEnabled then
        local myRoot = getHRP()
        local myPos = myRoot and myRoot.Position
        local screenBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        local targetsCopy = table.clone(activeTargets)
        for i = 1, #targetsCopy do
            if renderCount >= MAX_ESP_POOL then break end
            local t = targetsCopy[i]
            if t and t.root and t.root.Parent then
                local allowEsp = false
                if t.category == "Mob" and showMobs then allowEsp = true
                elseif t.category == "Boss" and showBosses then allowEsp = true
                elseif t.category == "Player" and showPlayers then allowEsp = true
                elseif t.category == "Bot" and showBots then allowEsp = true
                end
                if allowEsp then
                    local rootPos = t.root.Position
                    local dist = myPos and (myPos - rootPos).Magnitude or 0
                    if dist <= maxDist then
                        local screenPos, onScreen = WorldToScreen(rootPos)
                        if onScreen then
                            renderCount = renderCount + 1
                            local poolItem = espPool[renderCount]
                            local distInt = math.floor(dist)
                            local hpPercent = math.clamp(t.hp / t.maxHp, 0, 1)
                            local h = math.clamp(1700 / (dist + 1), 22, 220)
                            local w = h * 0.65
                            local topX = screenPos.X - (w / 2)
                            local topY = screenPos.Y - (h / 2)
                            local assignedColor = t.color or Color3.fromRGB(255, 255, 255)
                            if drawBox then
                                poolItem.box.Position = Vector2.new(topX, topY)
                                poolItem.box.Size = Vector2.new(w, h)
                                poolItem.box.Color = assignedColor
                                poolItem.box.Visible = true
                            else
                                poolItem.box.Visible = false
                            end
                            if showHpBar then
                                poolItem.barBg.Position = Vector2.new(topX - 6, topY)
                                poolItem.barBg.Size = Vector2.new(3, h)
                                poolItem.barBg.Visible = true
                                local fillH = math.floor(h * hpPercent)
                                poolItem.bar.Position = Vector2.new(topX - 6, topY + (h - fillH))
                                poolItem.bar.Size = Vector2.new(3, fillH)
                                poolItem.bar.Color = Color3.fromRGB(
                                    math.floor(255 * (1 - hpPercent)),
                                    math.floor(220 * hpPercent),
                                    50
                                )
                                poolItem.bar.Visible = true
                            else
                                poolItem.barBg.Visible = false
                                poolItem.bar.Visible = false
                            end
                            if showNames then
                                poolItem.nameTag.Position = Vector2.new(screenPos.X, topY - 16)
                                poolItem.nameTag.Text = string.format("[%s] %s", t.tagLabel, t.name)
                                poolItem.nameTag.Color = assignedColor
                                poolItem.nameTag.Visible = true
                            else
                                poolItem.nameTag.Visible = false
                            end
                            if showHpText or showDist then
                                local subTextParts = {}
                                if showHpText then
                                    table.insert(subTextParts, string.format("%d/%d HP", math.floor(t.hp), math.floor(t.maxHp)))
                                end
                                if showDist then
                                    table.insert(subTextParts, string.format("%dm", distInt))
                                end
                                poolItem.subTag.Position = Vector2.new(screenPos.X, topY + h + 3)
                                poolItem.subTag.Text = table.concat(subTextParts, " | ")
                                poolItem.subTag.Color = Color3.fromRGB(220, 220, 220)
                                poolItem.subTag.Visible = true
                            else
                                poolItem.subTag.Visible = false
                            end
                            if drawTracers then
                                poolItem.tracer.From = screenBottom
                                poolItem.tracer.To = Vector2.new(screenPos.X, topY + h)
                                poolItem.tracer.Color = assignedColor
                                poolItem.tracer.Visible = true
                            else
                                poolItem.tracer.Visible = false
                            end
                        end
                    end
                end
            end
        end
    end
    for idx = renderCount + 1, activeEspCount do
        hideESP(espPool[idx])
    end
    activeEspCount = renderCount
end)
local isUnloading = false
local function destroyHub(isReload)
    if isUnloading then return end
    isUnloading = true
    if _G.ANT_HUB_BOOT == SCRIPT_ID then
        _G.ANT_HUB_BOOT = nil
    end
    pcall(function() espConnection:Disconnect() end)
    for _, item in ipairs(espPool) do
        pcall(function()
            item.box:Remove()
            item.barBg:Remove()
            item.bar:Remove()
            item.nameTag:Remove()
            item.subTag:Remove()
            item.tracer:Remove()
        end)
    end
    pcall(function() LocalPlayer:SetAttribute("MagnetMult", 1) end)
    if not isReload then
        task.spawn(function()
            task.wait(0.08)
            pcall(function() UI.RemoveTab("Ant Hub") end)
            pcall(function() notify("Ant Hub", "Hub descarregado com sucesso!", 4) end)
            print("[AntHub] Hub completely unloaded.")
        end)
    end
end
_G.ANT_HUB_STOP = destroyHub
UI.AddTab("Ant Hub", function(tab)
    local mainSec = tab:Section("Features Menu", "Left", {"Free Edition", "Pro Edition"})
    if mainSec.page == 0 then
        mainSec:Text("--- Long-Range Combat (Free) ---")
        mainSec:Toggle("hitbox_on", "Enable Long-Range Reach")
        mainSec:Tip("Smoothly expands reach & root hitboxes for Mobs, Bosses and Ants")
        mainSec:SliderInt("hitbox_reach", "Attack Reach (Length)", 20, 160, 80)
        mainSec:SliderInt("hitbox_size", "Hitbox Box Size", 6, 25, 14)
        mainSec:Toggle("hitbox_mobs", "Hit Mobs & Critters", true)
        mainSec:Toggle("hitbox_bosses", "Hit Bosses & Elites", true)
        mainSec:Toggle("hitbox_players", "Hit Players", true)
        mainSec:Toggle("hitbox_bots", "Hit Bots", true)
        mainSec:Spacing()
        mainSec:Text("--- Defense & Anti-Damage (Free) ---")
        mainSec:Toggle("antiboss_aoe", "Boss Red Area Auto-Dodge")
        mainSec:Tip("Detects red warning telegraph areas and immediately dodges out before attack hits")
        mainSec:SliderInt("boss_dodge_dist", "Boss Dodge Distance", 15, 80, 35)
        mainSec:Toggle("antidmg_on", "Anti Damage (On Hit Dodge)")
        mainSec:SliderInt("dodge_dist", "On-Hit Dodge Distance", 10, 80, 25)
        mainSec:Toggle("keepaway_on", "Keep Distance (Auto Flee)")
        mainSec:SliderInt("keep_radius", "Safe Radius", 8, 80, 18)
        mainSec:Spacing()
        mainSec:Text("--- Movement & Farm (Free) ---")
        mainSec:Toggle("speed_on", "Speed Boost")
        mainSec:SliderInt("speed_val", "Speed Value", 16, 250, 60)
        mainSec:Toggle("fly_on", "Fly (Anti-Gravity)")
        mainSec:Toggle("magnet_on", "Auto Magnet (Orbs/Food)")
        mainSec:SliderInt("magnet_val", "Magnet Force", 10, 1000, 500)
    elseif mainSec.page == 1 then
        mainSec:Text("--- Auto Progression (Requires Pro) ---")
        mainSec:Toggle("auto_evo", "Auto Evolve (Requires Pro)")
        mainSec:Toggle("auto_rebirth", "Auto Rebirth (Requires Pro)")
        mainSec:Toggle("auto_upg", "Auto Upgrade (Requires Pro)")
        mainSec:Combo("upg_idx", "Target Upgrade", UPGRADE_LIST, 0)
        mainSec:Spacing()
        mainSec:Text("--- Rewards (Requires Pro) ---")
        mainSec:Toggle("rewards_auto", "Auto Claim Rewards (Requires Pro)")
        mainSec:Button("Claim All Now (Requires Pro)", function()
            task.spawn(function() claimAllRewards(false) end)
        end)
        mainSec:Button("Redeem Active Codes (Requires Pro)", function()
            task.spawn(redeemAllCodes)
        end)
    end
    local visSec = tab:Section("Visuals (Overlay ESP)", "Right")
    visSec:Toggle("esp_on", "Enable ESP")
    visSec:Toggle("esp_box", "2D Bounding Box")
    visSec:Toggle("esp_name", "Display Names & Stage")
    visSec:Toggle("esp_hp", "Health Bar")
    visSec:Toggle("esp_hp_text", "Health Numbers (HP)")
    visSec:Toggle("esp_dist", "Distance Numbers (m)")
    visSec:Toggle("esp_tracers", "Tracers (Snaplines)")
    visSec:SliderInt("esp_max_dist", "Max Render Distance", 50, 2000, 1000)
    visSec:Spacing()
    visSec:Text("Category Visibility:")
    visSec:Toggle("esp_bosses", "Bosses (Red: Spider/Beetle)", true)
    visSec:Toggle("esp_mobs", "Mobs (Green: Aphid/Ladybug)", true)
    visSec:Toggle("esp_players", "Players (Cyan Blue)", true)
    visSec:Toggle("esp_bots", "Bots (Yellow)", true)
    local cfgSec = tab:Section("Settings", "Right")
    cfgSec:Button("Save Settings", function() saveConfig() end)
    cfgSec:Button("Load Settings", function() loadConfig() end)
    cfgSec:Button("Unload Hub", function() destroyHub(false) end)
end)
print("[AntHub V3.5 STABLE] LOADED SUCCESSFULLY!")