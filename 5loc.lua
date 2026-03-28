local script = {}

local _hudFont = Render.LoadFont("Arial", 18, Enum.FontCreate.FONTFLAG_ANTIALIAS)
local _hudColor = Color(0, 255, 128, 255)

local KEY_ITEM_NAME = "item_prison_cell_key"
local DOOR_POS = Vector(-14428, 11654, 640) 
local BOSS_POS = Vector(-14912, 13559, 512)
local BOSS_NAME = "npc_dota_boss_tiny"
local START_BUY_POS = Vector(-15316, 7880, 640)
local LICH_HEART = "item_lich_heart"
local MOON_SHARD = "item_moon_shard"
local MEDUSA_FINAL_ITEM_SOLO = "item_trident_lua2"
local MEDUSA_FINAL_ITEM_TEAM = "item_trident_lua1"
local OTHER_FINAL_ITEM_SOLO = "item_dragon_lance_lua2"
local OTHER_FINAL_ITEM_TEAM = "item_dragon_lance_lua1"
local FINAL_ITEM_BUY_INTERVAL = 0.1

local hasTeammateCache = nil
local lastTeammateCheck = 0

local function HasTeammate()
    local now = os.clock()
    if hasTeammateCache ~= nil and (now - lastTeammateCheck) < 10.0 then
        return hasTeammateCache
    end
    lastTeammateCheck = now
    local me = Heroes.GetLocal()
    if not me then hasTeammateCache = false; return false end
    local allHeroes = Heroes.GetAll()
    for i = 1, #allHeroes do
        local hero = allHeroes[i]
        if hero and hero ~= me and Entity.IsSameTeam(me, hero) and not NPC.IsIllusion(hero) then
            hasTeammateCache = true
            return true
        end
    end
    hasTeammateCache = false
    return false
end

local WAYPOINTS = {
    Vector(-15379, 8001, 640),   -- 1  точка покупки
    Vector(-13601, 7822, 512),   -- 2
    Vector(-12499, 7466, 512),   -- 3
    Vector(-11729, 7137, 512),   -- 4
    Vector(-11010, 6667, 640),   -- 5
    Vector(-11558, 6461, 512),   -- 6  [Нычка 1]
    Vector(-11268, 7288, 512),   -- 7
    Vector(-10394, 7482, 512),   -- 8
    Vector(-9655, 7031, 516),    -- 9
    Vector(-9125, 7377, 640),    -- 10
    Vector(-8953, 7835, 640),    -- 11
    Vector(-8664, 7038, 640),    -- 12 [Нычка 2]
    Vector(-8838, 8704, 768),    -- 13
    Vector(-9278, 9194, 640),    -- 14
    Vector(-9505, 9530, 640),    -- 15
    Vector(-9908, 9927, 580),    -- 16
    Vector(-9500, 10191, 640),   -- 17 [Нычка 3]
    Vector(-10425, 10576, 512),  -- 18
    Vector(-11005, 10791, 640),  -- 19
    Vector(-11662, 10751, 640),  -- 20
    Vector(-12194, 10824, 640),  -- 21
    Vector(-12339, 10296, 512),  -- 22
    Vector(-11855, 9962, 512),   -- 23
    Vector(-11541, 9791, 512),   -- 24
    Vector(-11078, 9594, 512),   -- 25
    Vector(-11148, 9147, 512),   -- 26
    Vector(-11685, 8635, 640),   -- 27
    Vector(-12217, 9055, 640),   -- 28
    Vector(-12732, 9349, 512),   -- 29
    Vector(-13437, 8808, 512),   -- 30
    Vector(-14475, 8944, 512),   -- 31
    Vector(-14365, 9452, 640),   -- 32
    Vector(-14293, 10064, 640),  -- 33
    Vector(-15194, 11148, 512),  -- 34
    Vector(-15084, 10504, 640),  -- 35 [Нычка 4]
    Vector(-13152, 10656, 768),  -- 36 (пауза 0.5с, пиксель в пиксель)
}

local STASH_WPS = { [6] = true, [12] = true, [17] = true, [35] = true }


local currentWaypoint = 1
local lastMove = 0
local lastTreeCut = 0
local lastSwap = 0
local finalPathState = 0 
local evadeUntil = 0
local evadePos = nil

local swapBackNeeded = false
local swapTime = 0 
local itemToRestoreSlot = -1 
local pauseUntil = 0 

local stashArriveTime = 0
local isWaitingInStash = false

local wp23ArriveTime = 0

local doorArriveTime = 0 
local bossWasSeen = false 

local startupPhase = 0
local startupDone = false
local startupLastAction = 0
local startupFinalQuickBuyReady = false
local startupMoonShardQuickBuyReady = false
local moonShardConsumed = false
local lichHeartHandled = false
local level25DetectedByPoints = false
local lastSpellPointsCheckTime = 0
local dropAxeAfterStashKey = false
local lastAxeDropTime = 0
local hadKeyPrev = false
local lastMoveTarget = nil
local lastMoveTargetDist = 999999
local lastDodgeTime = 0
local lastAttackTarget = nil
local lastAttackTime = 0

local PROTECTED_KEYWORDS_5L = {
    "crit_blade", 
    "book_of_knowledge", 
    "universal", 
    "doom_sword", 
    "doom_spear", 
    "dark_moon_shard", 
    "item_lich_heart",
    "quelling_blade",
    "mana_plate"
}

local function GetFinalBuyItemName(h)
    local team = HasTeammate()
    if not h then return OTHER_FINAL_ITEM_SOLO end
    if NPC.GetUnitName(h) == "npc_dota_hero_medusa" then
        return team and MEDUSA_FINAL_ITEM_TEAM or MEDUSA_FINAL_ITEM_SOLO
    end
    -- Не-медуза всегда покупает dragon_lance_lua2
    return OTHER_FINAL_ITEM_SOLO
end

local function FindTeammateMedusa()
    local me = Heroes.GetLocal()
    if not me then return nil end
    local allHeroes = Heroes.GetAll()
    for i = 1, #allHeroes do
        local hero = allHeroes[i]
        if hero and hero ~= me and Entity.IsSameTeam(me, hero) and not NPC.IsIllusion(hero) then
            if NPC.GetUnitName(hero) == "npc_dota_hero_medusa" then
                return hero
            end
        end
    end
    return nil
end

local function FindTeammateHero()
    local me = Heroes.GetLocal()
    if not me then return nil end
    local allHeroes = Heroes.GetAll()
    for i = 1, #allHeroes do
        local hero = allHeroes[i]
        if hero and hero ~= me and Entity.IsSameTeam(me, hero) and not NPC.IsIllusion(hero) then
            return hero
        end
    end
    return nil
end

local function IsMedusa(h)
    return h and NPC.GetUnitName(h) == "npc_dota_hero_medusa"
end

local function FindItemByNameInMainOrBackpack(h, itemName)
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(h, i)
        if it and Ability.GetName(it) == itemName then
            return it, i
        end
    end
    return nil, -1
end

local function FindFreeMainSlot(h)
    for i = 0, 5 do
        if not NPC.GetItemByIndex(h, i) then
            return i
        end
    end
    return -1
end

local function ToQuickBuyName(itemName)
    if not itemName then return nil end
    if itemName:sub(1, 5) == "item_" then
        return itemName:sub(6)
    end
    return itemName
end

local function SetQuickBuyCompat(itemName)
    if not itemName then return false end
    if not Engine then return false end

    local qbName = ToQuickBuyName(itemName)
    local candidates = { itemName }
    if qbName and qbName ~= itemName then
        table.insert(candidates, qbName)
    end

    for _, name in ipairs(candidates) do
        if type(Engine.SetQuickBuy) == "function" then
            Engine.SetQuickBuy(name, true)
        end
        if type(Engine.SetQuikbuy) == "function" then
            Engine.SetQuikbuy(name, true)
        end
        if type(Engine.SetQuikBuy) == "function" then
            Engine.SetQuikBuy(name, true)
        end

        -- Fallback for builds where API method exists but does not actually populate quickbuy.
        Engine.ExecuteCommand("dota_quickbuy " .. name)
    end

    return true
end

local function Hero() return Heroes.GetLocal() end
local function PlayerMe()
    local h = Hero()
    if not h then return nil end
    local players = Players.GetAll()
    for _, p in ipairs(players) do
        if p and Player.GetAssignedHero(p) == h then return p end
    end
    return nil
end

local function HasKey(h)
    for i = 0, 8 do
        local item = NPC.GetItemByIndex(h, i)
        if item and Ability.GetName(item) == KEY_ITEM_NAME then return true end
    end
    return false
end

local function GetDistanceSafe(v1, v2)
    if not v1 or not v2 then return 999999 end
    return (v1 - v2):Length2D()
end

local function EstimateMedusaWaypoint(medusaPos)
    if not medusaPos then return #WAYPOINTS + 1 end
    local bestIdx = 1
    local bestDist = 999999
    for i = 1, #WAYPOINTS do
        local d = GetDistanceSafe(medusaPos, WAYPOINTS[i])
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
    end
    if bestDist < 250 then return bestIdx + 1 end
    return bestIdx
end

local function IsRouteEnemyName(eName)
    if not eName then return false end
    return eName:find("npc_dota_zone_4_unit_1")
        or eName:find("npc_dota_zone_4_unit_2")
        or eName:find("npc_dota_zone_4_unit_3")
        or eName:find("npc_dota_zone_4_unit_4")
        or eName:find("npc_dota_zone_4_unit_5")
end

local function FindAxeForDrop(h)
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(h, i)
        if it then
            local name = (Ability.GetName(it) or ""):lower()
            if name:find("quelling") then
                return it
            end
        end
    end
    return nil
end

local function GetAttackStandoff(hero)
    local base = 350
    if NPC.GetAttackRange then
        local r = NPC.GetAttackRange(hero)
        if r and r > 0 then
            base = r
        end
    end
    if base < 260 then base = 260 end
    if base > 700 then base = 700 end
    return base
end

local function IsEnemyOnPath(myPos, wpPos, enemyPos)
    if not myPos or not wpPos or not enemyPos then return false end

    local toWp = wpPos - myPos
    local toEn = enemyPos - myPos
    local lenWp = toWp:Length2D()
    local lenEn = toEn:Length2D()

    if lenEn > 900 then return false end
    if lenWp < 1 then return lenEn <= 900 end

    local dirWp = toWp:Normalized()
    local dirEn = toEn:Normalized()
    local dot = dirWp:Dot(dirEn)
    if dot < 0.2 then return false end

    local proj = toEn:Dot(dirWp)
    if proj < -50 or proj > lenWp + 220 then return false end

    local perpSq = math.max(0, lenEn * lenEn - proj * proj)
    local perp = math.sqrt(perpSq)
    return perp <= 380
end

local function FindPathTarget(myHero, myPos, wpPos, all_npcs)
    local best = nil
    local bestDist = 99999

    for i = 1, #all_npcs do
        local e = all_npcs[i]
        if e and Entity.IsAlive(e) and not Entity.IsSameTeam(myHero, e)
            and not (Entity.IsDormant and Entity.IsDormant(e)) then
            local eName = (NPC.GetUnitName(e) or ""):lower()
            if IsRouteEnemyName(eName) then
                local ePos = Entity.GetAbsOrigin(e)
                if ePos and IsEnemyOnPath(myPos, wpPos, ePos) then
                    local d = GetDistanceSafe(myPos, ePos)
                    if d < bestDist then
                        bestDist = d
                        best = e
                    end
                end
            end
        end
    end

    return best
end

local function IsValidCombatEnemy(myHero, e)
    if not e or not Entity.IsAlive(e) then return false end
    if Entity.IsSameTeam(myHero, e) then return false end
    if Entity.IsDormant and Entity.IsDormant(e) then return false end

    local eName = (NPC.GetUnitName(e) or ""):lower()
    if eName == "" then return false end
    if eName:find("courier") then return false end
    if eName:find("ward") then return false end
    if not IsRouteEnemyName(eName) then return false end

    return true
end

local function FindNearestCombatEnemy(myHero, centerPos, radius, all_npcs)
    local best = nil
    local bestDist = radius + 1

    for i = 1, #all_npcs do
        local e = all_npcs[i]
        if IsValidCombatEnemy(myHero, e) then
            local ePos = Entity.GetAbsOrigin(e)
            if ePos then
                local d = GetDistanceSafe(centerPos, ePos)
                if d <= radius and d < bestDist then
                    bestDist = d
                    best = e
                end
            end
        end
    end

    return best, bestDist
end

local function IsProtected(itemName)
    if not itemName then return false end
    itemName = itemName:lower()
    for _, key in ipairs(PROTECTED_KEYWORDS_5L) do
        if itemName:find(key) then
            return true
        end
    end
    return false
end

function script.OnUpdate()
    if _G.GlobalPhase ~= 7 then return end

    local h = Hero()
    if not h or not Entity.IsAlive(h) then return end
    local pMe = PlayerMe()
    if not pMe then return end
    local myPos = Entity.GetAbsOrigin(h)
    if not myPos then return end
    local now = os.clock()

    -- При достижении 25 spell points (детект по сумме уровней абилок/талантов) выбрасываем item_lich_heart.
    if not lichHeartHandled then
        local isMedu = IsMedusa(h)
        local hasTeam = HasTeammate()

        -- Медуза с тиммейтом: полностью игнорирует lich_heart
        if isMedu and hasTeam then
            lichHeartHandled = true
        else
            if not level25DetectedByPoints and (now - lastSpellPointsCheckTime) > 1.5 then
                lastSpellPointsCheckTime = now

                local spent = 0
                for i = 0, 31 do
                    local abil = NPC.GetAbilityByIndex(h, i)
                    if abil then
                        local l = Ability.GetLevel(abil)
                        if l and type(l) == "number" and l > 0 then
                            spent = spent + l
                        end
                    end
                end

                -- Порог события: 25 spell points.
                if spent >= 25 then
                    level25DetectedByPoints = true
                end
            end

            if level25DetectedByPoints then
                local heart, _ = FindItemByNameInMainOrBackpack(h, LICH_HEART)
                if heart then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, heart, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastSwap = now
                    lichHeartHandled = true
                    return
                end
            end
        end
    end

    -- Ключ появился в инвентаре: если это произошло в нычке, сразу выбрасываем топорик на землю.
    -- Важно: делаем это ДО паузы, чтобы дроп не задерживался swap/pause логикой.
    local keyInInv = HasKey(h)
    local keyAvailable = keyInInv
    if not keyAvailable and HasTeammate() then
        local mate = IsMedusa(h) and FindTeammateHero() or FindTeammateMedusa()
        if mate and not Entity.IsDormant(mate) then keyAvailable = HasKey(mate) end
    end
    local keyJustFound = keyInInv and not hadKeyPrev
    hadKeyPrev = keyInInv

    if keyJustFound then
        dropAxeAfterStashKey = true
    end

    if keyInInv and (dropAxeAfterStashKey or (keyJustFound and isWaitingInStash)) and (now - lastAxeDropTime) >= 0.05 then
        lastAxeDropTime = now
        local axeItem = FindAxeForDrop(h)
        if axeItem and itemToRestoreSlot >= 0 then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, itemToRestoreSlot, Vector(0,0,0), axeItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            swapBackNeeded = false
            dropAxeAfterStashKey = false
            pauseUntil = now + 0.1
            return
        end
        dropAxeAfterStashKey = false
    end

    if now < pauseUntil then return end

    -- СТАРТОВАЯ ФАЗА: прийти в точку -> купить+съесть moon shard -> купить trident -> свап из ранца
    if not startupDone then
        _G.HeroMove = "[5loc] Startup"
        _G.HeroAction = "[5loc] Startup phase " .. startupPhase
        if startupPhase == 0 then
            -- Подходим к точке покупки
            local distToBuyPos = GetDistanceSafe(myPos, START_BUY_POS)
            if distToBuyPos > 150 then
                if now - lastMove >= 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, START_BUY_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                startupPhase = 1
                startupLastAction = now
            end
            return
        elseif startupPhase == 1 then
            -- Покупаем Moon Shard, свапаем в активный слот и съедаем
            if not moonShardConsumed then
                local ms, msSlot = FindItemByNameInMainOrBackpack(h, MOON_SHARD)
                if ms then
                    if msSlot > 5 then
                        -- Свапаем из ранца в активный слот
                        if now - startupLastAction >= 0.35 then
                            local freeSlot = FindFreeMainSlot(h)
                            if freeSlot >= 0 then
                                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, freeSlot, Vector(0,0,0), ms, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            else
                                for i = 0, 5 do
                                    local it = NPC.GetItemByIndex(h, i)
                                    if it and not IsProtected(Ability.GetName(it)) then
                                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, i, Vector(0,0,0), ms, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                                        break
                                    end
                                end
                            end
                            startupLastAction = now
                        end
                        return
                    end
                    -- Уже в активном слоте — съедаем
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, h, Vector(0,0,0), ms, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    moonShardConsumed = true
                    startupLastAction = now
                    pauseUntil = now + 0.5
                    return
                end
                if now - startupLastAction >= FINAL_ITEM_BUY_INTERVAL then
                    if not startupMoonShardQuickBuyReady then
                        Engine.ExecuteCommand("dota_clear_quickbuy")
                        SetQuickBuyCompat(MOON_SHARD)
                        startupMoonShardQuickBuyReady = true
                    end
                    Engine.ExecuteCommand("dota_purchase_quickbuy")
                    startupLastAction = now
                end
                return
            end
            startupPhase = 2
            startupLastAction = now
            return
        elseif startupPhase == 2 then
            -- Покупаем item_trident_lua2
            if now - startupLastAction >= FINAL_ITEM_BUY_INTERVAL then
                local finalItemName = GetFinalBuyItemName(h)
                local finalItem, itemSlot = FindItemByNameInMainOrBackpack(h, finalItemName)

                if finalItem then
                    if itemSlot <= 5 then
                        startupPhase = 4
                        startupLastAction = now
                        return
                    end
                    startupPhase = 3
                    startupLastAction = now
                    return
                end

                if not startupFinalQuickBuyReady then
                    Engine.ExecuteCommand("dota_clear_quickbuy")
                    SetQuickBuyCompat(finalItemName)
                    startupFinalQuickBuyReady = true
                end
                Engine.ExecuteCommand("dota_purchase_quickbuy")
                startupLastAction = now
            end
            return
        elseif startupPhase == 3 then
            -- Свап item_trident_lua2 из ранца в активный слот (0-5), не трогая protected-предметы.
            local finalItemName = GetFinalBuyItemName(h)
            local finalItem, itemSlot = FindItemByNameInMainOrBackpack(h, finalItemName)

            if finalItem and itemSlot > 5 then
                if now - startupLastAction >= 0.35 then
                    local freeSlot = FindFreeMainSlot(h)
                    if freeSlot >= 0 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, freeSlot, Vector(0,0,0), finalItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        startupLastAction = now
                        startupPhase = 4
                        return
                    end

                    for i = 0, 5 do
                        local it = NPC.GetItemByIndex(h, i)
                        if it and not IsProtected(Ability.GetName(it)) then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, i, Vector(0,0,0), finalItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            startupLastAction = now
                            startupPhase = 4
                            return
                        end
                    end

                    startupPhase = 4
                    startupLastAction = now
                end
                return
            end

            startupPhase = 4
            startupLastAction = now
            return
        elseif startupPhase == 4 then
            startupDone = true
            pauseUntil = now + 0.2
            return
        end
    end

    -- ПРОВЕРКА ХП
    local hpPct = Entity.GetHealth(h) / Entity.GetMaxHealth(h)
    if hpPct < 0.25 then
        _G.HeroMove = "[5loc] Escaping (HP low)"
        _G.HeroAction = "[5loc] LOW HP escape"

        -- Non-Medusa в команде: убегает К Медузе, а не назад по вейпоинтам
        local escapePos = nil
        if HasTeammate() and not IsMedusa(h) then
            local medusa = FindTeammateMedusa()
            if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                escapePos = Entity.GetAbsOrigin(medusa)
                _G.HeroAction = "[5loc] LOW HP -> run to Medusa"
            end
        end
        if not escapePos then
            local escapeWpIndex = currentWaypoint - 1
            if escapeWpIndex < 1 then escapeWpIndex = 1 end
            escapePos = WAYPOINTS[escapeWpIndex]
        end

        if now - lastMove >= 0.35 then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, escapePos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastMove = now
        end
        return 
    end

    local all_npcs = NPCs.GetAll()

    -- 1. ДОДЖ ПАУКОВ
    for i = 1, #all_npcs do
        local e = all_npcs[i]
        if e and not Entity.IsSameTeam(h, e) and not Entity.IsAlive(e) then
            local eName = (NPC.GetUnitName(e) or ""):lower()
            if eName:find("npc_dota_zone_4_unit_3") then
                local ePos = Entity.GetAbsOrigin(e)
                if ePos and GetDistanceSafe(myPos, ePos) < 180 then
                    evadePos = ePos; evadeUntil = now + 0.8
                end
            end
        end
    end

    if now < evadeUntil and evadePos then
        _G.HeroMove = "[5loc] Dodging away"
        _G.HeroAction = "[5loc] Dodge spider!"
        if now - lastMove >= 0.15 then
            local runPos = myPos + (myPos - evadePos):Normalized() * 400
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, runPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastMove = now
        end
        return 
    end

    -- 2. ДОДЖ СТРЕЛ (все снаряды, не только ближайший)
    local linears = {}
    if LinearProjectiles and LinearProjectiles.GetAll then
        linears = LinearProjectiles.GetAll()
    end

    local dangerousProjs = {}
    for _, proj in pairs(linears) do
        if proj and proj.position and proj.velocity then
            local projPos = proj.position
            local distToProj = GetDistanceSafe(myPos, projPos)
            if distToProj < 800 then
                local vel = proj.velocity
                if vel and (vel.x ~= 0 or vel.y ~= 0) then
                    local projDir = Vector(vel.x, vel.y, 0):Normalized()
                    local dirToHero = (myPos - projPos):Normalized()
                    local dot = dirToHero:Dot(projDir)
                    if dot > 0 then
                        local toHero = myPos - projPos
                        local proj_along = toHero:Dot(projDir)
                        local perpSq = math.max(0, distToProj * distToProj - proj_along * proj_along)
                        local perpDist = math.sqrt(perpSq)
                        if perpDist < 300 then
                            table.insert(dangerousProjs, {
                                pos = projPos,
                                dir = projDir,
                                dist = distToProj,
                                perp = perpDist
                            })
                        end
                    end
                end
            end
        end
    end

    if #dangerousProjs > 0 then
        _G.HeroMove = "[5loc] Dodging arrows"
        _G.HeroAction = "[5loc] Dodge arrow! (" .. #dangerousProjs .. ")"
        local dodgeVec = Vector(0, 0, 0)
        for _, p in ipairs(dangerousProjs) do
            local perpDir = Vector(-p.dir.y, p.dir.x, 0):Normalized()
            local toHero = myPos - p.pos
            local side = toHero.x * (-p.dir.y) + toHero.y * p.dir.x
            if side < 0 then perpDir = perpDir * (-1) end
            local weight = 1.0 + (800 - p.dist) / 300
            dodgeVec = dodgeVec + perpDir * weight
        end
        local dodgeDir = dodgeVec:Normalized()
        local dodgeDist = 50 + #dangerousProjs * 15
        if dodgeDist > 120 then dodgeDist = 120 end
        local targetPos = myPos + dodgeDir * dodgeDist

        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
        -- После доджа сразу ставим в очередь атаку ближайшего врага, чтобы герой не простаивал
        local dodgeShooter, _ = FindNearestCombatEnemy(h, myPos, 800, all_npcs)
        if dodgeShooter then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, dodgeShooter, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, true, true)
            lastAttackTarget = dodgeShooter
            lastAttackTime = now
        end
        lastMove = now
        lastDodgeTime = now
        return
    end

    -- 2.7. КАСТ 2 СКИЛЛА (W) при мане < 20%
    local manaPct = NPC.GetMana(h) / NPC.GetMaxMana(h)
    if manaPct < 0.20 then
        local abilW = NPC.GetAbilityByIndex(h, 1)
        if abilW and Ability.IsReady(abilW) and Ability.GetLevel(abilW) > 0 then
            local castTarget, _ = FindNearestCombatEnemy(h, myPos, 800, all_npcs)
            if castTarget then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, castTarget, Vector(0,0,0), abilW, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
                return
            end
        end
    end

    -- 3. СКАН ИНВЕНТАРЯ
    local qb = nil
    local qbSlot = -1
    local bf = nil

    for i = 0, 8 do
        local it = NPC.GetItemByIndex(h, i)
        if it then
            local name = Ability.GetName(it)
            if name:find("quelling") then qb = it; qbSlot = i end
            if i <= 5 and (name:find("bfury") or name:find("battlefury")) then bf = it end
        end
    end

    
    local bestTarget = nil
    local minDist = 1000
    local bossAliveNow = false

    for i = 1, #all_npcs do
        local e = all_npcs[i]
        if e and Entity.IsAlive(e) and not Entity.IsSameTeam(h, e) then
            local eName = (NPC.GetUnitName(e) or ""):lower()
            local ePos = Entity.GetAbsOrigin(e)
            
            if ePos then
                local dist = GetDistanceSafe(myPos, ePos)

                if eName:find(BOSS_NAME) then
                    bossAliveNow = true
                    bossWasSeen = true
                    if dist < 1000 then
                        bestTarget = e
                        break 
                    end
                end

                if not bestTarget and dist < 750 then
                    if IsRouteEnemyName(eName) then
                        if dist < minDist then
                            minDist = dist
                            bestTarget = e
                        end
                    end
                end
            end
        end
    end

    
    if bossWasSeen and not bossAliveNow then
        _G.HeroMove = "[5loc] Standing"
        _G.HeroAction = "[5loc] Boss dead -> Phase 8"
        _G.GlobalPhase = 8
        return
    end

    -- ПРИОРИТЕТ АТАКИ вне маршрутной фазы
    if bestTarget and finalPathState ~= 0 then
        _G.HeroMove = "[5loc] In combat (boss area)"
        _G.HeroAction = "[5loc] ATK boss area"
        if bestTarget ~= lastAttackTarget or (now - lastAttackTime) >= 0.5 then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
            lastAttackTarget = bestTarget
            lastAttackTime = now
            lastMove = now
        end
        return 
    end

    
    if swapBackNeeded and (not isWaitingInStash or keyInInv) then
        if now - lastSwap >= 0.8 then
            local itemInZero = NPC.GetItemByIndex(h, 0)
            if itemInZero and Ability.GetName(itemInZero):find("quelling") then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, itemToRestoreSlot, Vector(0,0,0), itemInZero, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                swapBackNeeded = false
                lastSwap = now
                pauseUntil = now + 4.1 
                return 
            end
        end
    end

    if keyInInv and qb and not swapBackNeeded then
        if now - lastSwap >= 1.0 then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, qb, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastSwap = now
            return
        end
    end

    
    if finalPathState == 0 then
        -- ===== Non-Medusa в команде: следует позади Медузы, подбирает предметы =====
        if HasTeammate() and not IsMedusa(h) then
            -- ВЫСШИЙ ПРИОРИТЕТ: сканируем ключ на земле — бросаем ВСЕ дела и бежим подбирать
            local mapItems = PhysicalItems.GetAll()
            for _, item in pairs(mapItems) do
                if item and not Entity.IsDormant(item) then
                    local d = PhysicalItem.GetItem(item)
                    if d and Ability.GetName(d) == KEY_ITEM_NAME then
                        local kPos = Entity.GetAbsOrigin(item) or PhysicalItem.GetPosition(item)
                        if kPos then
                            local distToKey = GetDistanceSafe(myPos, kPos)
                            if distToKey > 150 then
                                _G.HeroMove = "[5loc] Rushing to key (" .. math.floor(distToKey) .. ")"
                                _G.HeroAction = "[5loc] KEY FOUND! Running!"
                                if now - lastMove >= 0.3 then
                                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, kPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                                    lastMove = now
                                end
                            else
                                _G.HeroMove = "[5loc] Picking up key"
                                _G.HeroAction = "[5loc] Found key!"
                                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, item, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            end
                            return
                        end
                    end
                end
            end
            -- Атакуем ближайших врагов
            local nearbyEnemy, _ = FindNearestCombatEnemy(h, myPos, 750, all_npcs)
            if nearbyEnemy then
                _G.HeroMove = "[5loc] In combat (follow)"
                _G.HeroAction = "[5loc] ATK nearby enemy"
                if nearbyEnemy ~= lastAttackTarget or (now - lastAttackTime) >= 0.5 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, nearbyEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                    lastAttackTarget = nearbyEnemy
                    lastAttackTime = now
                    lastMove = now
                end
                return
            end
            -- Следуем позади Медузы (75 юнитов назад от направления движения)
            local medusa = FindTeammateMedusa()
            if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                local medusaPos = Entity.GetAbsOrigin(medusa)
                local wpIdx = math.min(currentWaypoint, #WAYPOINTS)
                local wpTarget = WAYPOINTS[wpIdx]
                local dir = (wpTarget - medusaPos):Normalized()
                local behindPos = medusaPos - dir * 75
                local distToBehind = GetDistanceSafe(myPos, behindPos)
                _G.HeroMove = "[5loc] Behind Medusa (" .. math.floor(distToBehind) .. ")"
                _G.HeroAction = "[5loc] Following"
                if distToBehind > 50 and now - lastMove >= 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, behindPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
                -- Синхронизируем вейпоинт с Медузой
                local medusaWP = EstimateMedusaWaypoint(medusaPos)
                if medusaWP > 0 then currentWaypoint = math.max(1, medusaWP) end
                -- Переход к двери/боссу: если ключ есть и Медуза у двери или на последних WP
                if keyAvailable and (GetDistanceSafe(medusaPos, DOOR_POS) < 600 or currentWaypoint >= #WAYPOINTS) then
                    finalPathState = 1
                end
            else
                -- Медуза не видна: идём к вейпоинту самостоятельно
                local wpPos = WAYPOINTS[math.min(currentWaypoint, #WAYPOINTS)]
                if now - lastMove >= 0.5 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wpPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
                _G.HeroMove = "[5loc] WP" .. currentWaypoint .. " (solo fallback)"
                _G.HeroAction = "[5loc] Medusa not visible"
            end
            return
        end
        -- ===== Конец блока Non-Medusa =====

        local wpPos = WAYPOINTS[currentWaypoint]
        local distToWp = GetDistanceSafe(myPos, wpPos)
        _G.HeroMove = "[5loc] Patrol WP" .. currentWaypoint .. "/" .. #WAYPOINTS .. " (" .. math.floor(distToWp) .. ")"
        _G.HeroAction = "[5loc] Searching enemies"
        local isStash = STASH_WPS[currentWaypoint]

        -- ТОЛЬКО если ключ был поднят в нычке: возвращаем топорик на место.
        if dropAxeAfterStashKey and keyInInv and (now - lastAxeDropTime) >= 0.25 then
            local axeItem = FindAxeForDrop(h)
            lastAxeDropTime = now

            if axeItem and itemToRestoreSlot >= 0 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, itemToRestoreSlot, Vector(0,0,0), axeItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                swapBackNeeded = false
                dropAxeAfterStashKey = false
                return
            end

            -- Топорика нет: завершаем одноразовый сценарий, чтобы не зациклиться.
            dropAxeAfterStashKey = false
        end

        -- Пока рядом есть враги, не двигаем прогрессию маршрута: сначала зачищаем локальную область.
        local nearbyEnemy, nearbyEnemyDist = FindNearestCombatEnemy(h, myPos, 750, all_npcs)
        if nearbyEnemy then
            _G.HeroMove = "[5loc] In combat"
            _G.HeroAction = "[5loc] ATK nearby enemy"
            if nearbyEnemy ~= lastAttackTarget or (now - lastAttackTime) >= 0.5 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, nearbyEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                lastAttackTarget = nearbyEnemy
                lastAttackTime = now
                lastMove = now
            end
            return
        end

        local enemyNearWp, _ = FindNearestCombatEnemy(h, wpPos, 400, all_npcs)
        local mustClearBeforeMove = enemyNearWp ~= nil

        -- На маршруте сначала бьем врагов по линии движения и только потом наступаем на вейпоинт.
        local pathTarget = FindPathTarget(h, myPos, wpPos, all_npcs)
        if pathTarget then
            _G.HeroMove = "[5loc] Engaging path enemy"
            _G.HeroAction = "[5loc] ATK path enemy"
            if pathTarget ~= lastAttackTarget or (now - lastAttackTime) >= 1.5 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, pathTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                lastAttackTarget = pathTarget
                lastAttackTime = now
                lastMove = now
            end
            return
        end

        -- Если у целевого вейпоинта есть враг, но он не попал в pathTarget,
        -- все равно идем/бьем его, чтобы не зависать на месте с блокировкой движения.
        if mustClearBeforeMove and enemyNearWp then
            if enemyNearWp ~= lastAttackTarget or (now - lastAttackTime) >= 1.5 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, enemyNearWp, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                lastAttackTarget = enemyNearWp
                lastAttackTime = now
                lastMove = now
            end
            return
        end

        -- Если это нычка и есть ключ - пропускаем
        if keyAvailable and isStash then
            if distToWp < 600 and not mustClearBeforeMove then 
                currentWaypoint = currentWaypoint + 1
                isWaitingInStash = false
                stashArriveTime = 0
                return
            end
        end

        -- Входим в логику нычки
        if isStash and distToWp < 550 then
            _G.HeroMove = "[5loc] At stash WP" .. currentWaypoint
            _G.HeroAction = "[5loc] Stash WP" .. currentWaypoint .. " (cutting trees)"
            isWaitingInStash = true
            if stashArriveTime == 0 then stashArriveTime = now end

            local activeTool = bf
            local isUsingBackpackQB = false
            if not activeTool then
                if qb and qbSlot <= 5 then activeTool = qb
                elseif qb and qbSlot >= 6 and not swapBackNeeded then
                    if now - lastSwap >= 0.8 then
                        itemToRestoreSlot = qbSlot 
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), qb, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        swapBackNeeded = true
                        swapTime = now; lastSwap = now
                        return
                    end
                    isUsingBackpackQB = true
                end
            end

            local toolReady = activeTool and (not isUsingBackpackQB or (now - swapTime >= 6.0))
            local readyTool = toolReady and activeTool or nil
            -- На нычке 4 (WP 35) проверяем врагов в радиусе 800, на остальных — 400.
            -- Рубка деревьев начинается в любой нычке ТОЛЬКО если врагов нет.
            local stashCheckRadius = (currentWaypoint == 35) and 800 or 400
            local stashEnemy, _ = FindNearestCombatEnemy(h, myPos, stashCheckRadius, all_npcs)
            if stashEnemy then
                if stashEnemy ~= lastAttackTarget or (now - lastAttackTime) >= 1.5 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, stashEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                    lastAttackTarget = stashEnemy
                    lastAttackTime = now
                    lastMove = now
                end
                return
            end

            if readyTool and Ability.IsReady(readyTool) and now - lastTreeCut >= 1.0 then
                local trees = Trees.InRadius(myPos, 220, true)
                local blocker = nil
                local bestBlockerScore = -1
                for _, tree in pairs(trees) do
                    local tPos = Entity.GetAbsOrigin(tree)
                    local dirToWp = (wpPos - myPos):Normalized()
                    local dirToTree = (tPos - myPos):Normalized()
                    local dot = dirToWp:Dot(dirToTree)
                    if dot > 0.2 then 
                        local score = dot + (1 - (GetDistanceSafe(myPos, tPos) / 220))
                        if score > bestBlockerScore then bestBlockerScore = score; blocker = tree end
                    end
                end
                if blocker then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, Entity.GetIndex(blocker), Vector(0,0,0), readyTool, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastTreeCut = now
                    return 
                end
            end

            local mapItems = PhysicalItems.GetAll()
            local targetKey = nil
            for _, item in pairs(mapItems) do
                if item and not Entity.IsDormant(item) then
                    local d = PhysicalItem.GetItem(item)
                    if d and Ability.GetName(d) == KEY_ITEM_NAME then
                        local kPos = Entity.GetAbsOrigin(item) or PhysicalItem.GetPosition(item)
                        if kPos and GetDistanceSafe(kPos, wpPos) < 1000 then targetKey = item; break end
                    end
                end
            end

            if targetKey then
                -- В команде Медуза не подбирает ключ — его подберёт тиммейт
                if IsMedusa(h) and HasTeammate() then
                    isWaitingInStash = false
                    stashArriveTime = 0
                    currentWaypoint = currentWaypoint + 1
                    return
                end
                local kPos = Entity.GetAbsOrigin(targetKey) or PhysicalItem.GetPosition(targetKey)
                if GetDistanceSafe(myPos, kPos) > 150 then
                    if now - lastMove >= 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, kPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMove = now
                    end
                else
                    dropAxeAfterStashKey = true
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, targetKey, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                end
                return
            end

            if now - lastMove >= 0.5 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wpPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end

            if now - stashArriveTime > 14.0 then
                isWaitingInStash = false
                stashArriveTime = 0
                currentWaypoint = currentWaypoint + 1
            end
            return
        end

        local arrivalDist = (currentWaypoint == 36) and 40 or 180

        if distToWp < arrivalDist and not mustClearBeforeMove then
            -- Вейпоинт 36: ждём 0.5с на точке (пиксель в пиксель)
            if currentWaypoint == 36 then
                if wp23ArriveTime == 0 then
                    wp23ArriveTime = now
                end
                if now - wp23ArriveTime < 0.5 then
                    if now - lastMove >= 0.15 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wpPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMove = now
                    end
                    return
                end
                wp23ArriveTime = 0
            end

            -- Non-Medusa с тиммейтом: не может обогнать Медузу по вейпоинтам
            if HasTeammate() and not IsMedusa(h) then
                local medusa = FindTeammateMedusa()
                if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                    local medusaPos = Entity.GetAbsOrigin(medusa)
                    local medusaWP = EstimateMedusaWaypoint(medusaPos)
                    if currentWaypoint + 1 > medusaWP then
                        return
                    end
                end
            end

            isWaitingInStash = false
            stashArriveTime = 0
            if currentWaypoint == #WAYPOINTS then
                if keyAvailable then finalPathState = 1 else currentWaypoint = 1 end
            else 
                currentWaypoint = currentWaypoint + 1 
            end
        elseif not mustClearBeforeMove and now - lastMove >= 0.5 then
            -- Антиосцилляция: не спамим move если уже идём к тому же вейпоинту и дистанция уменьшается.
            -- Но если застряли дольше 2с — принудительно переотправляем команду.
            local curDist = distToWp
            local forceMove = (now - lastMove) >= 2.0
            if not forceMove and lastMoveTarget == currentWaypoint and curDist < lastMoveTargetDist and (lastMoveTargetDist - curDist) > 5 then
                lastMoveTargetDist = curDist
            else
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wpPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
                lastMoveTarget = currentWaypoint
                lastMoveTargetDist = curDist
            end
        end

    elseif finalPathState == 1 then
        local distToDoor = GetDistanceSafe(myPos, DOOR_POS)
        _G.HeroMove = "[5loc] Moving to door (" .. math.floor(distToDoor) .. ")"
        _G.HeroAction = "[5loc] Go to door"
        if distToDoor > 100 then
            if now - lastMove >= 0.35 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, DOOR_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            if doorArriveTime == 0 then doorArriveTime = now end
            if now - doorArriveTime > 1.2 then
                finalPathState = 2
            end
        end
    elseif finalPathState == 2 then
        local distToBoss = GetDistanceSafe(myPos, BOSS_POS)
        _G.HeroMove = "[5loc] Boss arena (" .. math.floor(distToBoss) .. ")"
        _G.HeroAction = "[5loc] Waiting for boss"
        
        if distToBoss > 250 then
            if now - lastMove >= 0.35 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, BOSS_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            -- Здесь только удерживаем позицию у босса.
            -- Переход в фазу 8 делается выше только после подтвержденной смерти босса.
            if now - lastMove >= 0.8 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        end
    end
end

function script.OnDraw()
    if _G.GlobalPhase ~= 7 then return end
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end
    local pos = Entity.GetAbsOrigin(h)
    if not pos then return end
    local headPos = pos + Vector(0, 0, 200)
    local screenPos, vis = Render.WorldToScreen(headPos)
    if vis and screenPos then
        local moveColor = Color(100, 200, 255, 255)
        local actColor  = Color(0, 255, 128, 255)
        if _G.HeroMove then
            Render.Text(_hudFont, 18, _G.HeroMove, screenPos, moveColor)
        end
        if _G.HeroAction then
            local line2 = screenPos + Vector(0, 22, 0)
            Render.Text(_hudFont, 18, _G.HeroAction, line2, actColor)
        end
    end
end

return script
