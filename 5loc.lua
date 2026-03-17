local script = {}


local KEY_ITEM_NAME = "item_prison_cell_key"
local DOOR_POS = Vector(-14430, 11679, 640) 
local BOSS_POS = Vector(-14797, 13594, 512)
local BOSS_NAME = "npc_dota_boss_tiny"
local START_BUY_POS = Vector(-15316, 7880, 640)
local LICH_HEART = "item_lich_heart"
local MOON_SHARD = "item_moon_shard"
local MEDUSA_FINAL_ITEM = "item_trident_lua2"
local OTHER_FINAL_ITEM = "item_trident_lua2"
local FINAL_ITEM_BUY_INTERVAL = 0.2

local WAYPOINTS = {
    Vector(-12696, 7568, 512),   -- 1
    Vector(-11930, 7228, 512),   -- 2
    Vector(-11164, 6741, 640),   -- 3
    Vector(-11559, 6489, 512),   -- 4 [Нычка 1]
    Vector(-9465, 6718, 512),    -- 5
    Vector(-9387, 7097, 639),    -- 6
    Vector(-8665, 7040, 640),    -- 7 [Нычка 2]
    Vector(-8783, 8491, 768),    -- 8
    Vector(-9918, 9708, 640),    -- 9
    Vector(-9574, 10225, 640),   -- 10 [Нычка 3]
    Vector(-10310, 10515, 512),  -- 11
    Vector(-11021, 10871, 640),  -- 12
    Vector(-11754, 10643, 640),  -- 13
    Vector(-12197, 10447, 512),  -- 14
    Vector(-11772, 9912, 512),   -- 15
    Vector(-10912, 9632, 512),   -- 16
    Vector(-11420, 8666, 640),   -- 17
    Vector(-12412, 9173, 600),   -- 18
    Vector(-12790, 8228, 512),   -- 19
    Vector(-15003, 8904, 512),   -- 20
    Vector(-14260, 9282, 640),   -- 21
    Vector(-15335, 10478, 640),  -- 22 [Нычка 4]
    Vector(-14092, 10373, 640),  -- 23
}

local STASH_WPS = { [4] = true, [7] = true, [10] = true, [22] = true }


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
    if not h then return OTHER_FINAL_ITEM end
    if NPC.GetUnitName(h) == "npc_dota_hero_medusa" then
        return MEDUSA_FINAL_ITEM
    end
    return OTHER_FINAL_ITEM
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
        if e and Entity.IsAlive(e) and not Entity.IsSameTeam(myHero, e) then
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
    if GlobalPhase ~= 7 then return end

    local h = Hero()
    if not h or not Entity.IsAlive(h) then return end
    local pMe = PlayerMe()
    if not pMe then return end
    local myPos = Entity.GetAbsOrigin(h)
    if not myPos then return end
    local now = os.clock()

    -- При достижении 25 spell points (детект по сумме уровней абилок/талантов) выбрасываем item_lich_heart.
    if not lichHeartHandled then
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
            else
                -- Lich heart нет в инвентаре — считаем задачу выполненной
                lichHeartHandled = true
            end
        end
    end

    -- Ключ появился в инвентаре: если это произошло в нычке, сразу выбрасываем топорик на землю.
    -- Важно: делаем это ДО паузы, чтобы дроп не задерживался swap/pause логикой.
    local keyInInv = HasKey(h)
    local keyJustFound = keyInInv and not hadKeyPrev
    hadKeyPrev = keyInInv

    if keyJustFound then
        dropAxeAfterStashKey = true
    end

    if keyInInv and (dropAxeAfterStashKey or (keyJustFound and isWaitingInStash)) and (now - lastAxeDropTime) >= 0.05 then
        lastAxeDropTime = now
        local axeItem = FindAxeForDrop(h)
        if axeItem then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, axeItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            dropAxeAfterStashKey = false
            pauseUntil = now + 0.1
            return
        end
        dropAxeAfterStashKey = false
    end

    if now < pauseUntil then return end

    -- СТАРТОВАЯ ФАЗА: прийти в точку -> купить+съесть moon shard -> купить trident -> свап из ранца
    if not startupDone then
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
            -- Покупаем Moon Shard и съедаем
            if not moonShardConsumed then
                local ms, msSlot = FindItemByNameInMainOrBackpack(h, MOON_SHARD)
                if ms then
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
        local escapeWpIndex = currentWaypoint - 1
        if escapeWpIndex < 1 then escapeWpIndex = 1 end
        local escapePos = WAYPOINTS[escapeWpIndex]
        local distToEscape = GetDistanceSafe(myPos, escapePos)
        
        if distToEscape > 250 then
            if now - lastMove >= 0.35 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, escapePos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            local currentHpPct = Entity.GetHealth(h) / Entity.GetMaxHealth(h)
            if currentHpPct < 0.25 then
                local furtherWpIndex = currentWaypoint - 2
                if furtherWpIndex < 1 then furtherWpIndex = 1 end
                local furtherEscapePos = WAYPOINTS[furtherWpIndex]
                if now - lastMove >= 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, furtherEscapePos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if now - lastMove >= 0.5 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, escapePos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            end
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
        if now - lastMove >= 0.15 then
            local runPos = myPos + (myPos - evadePos):Normalized() * 400
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, runPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastMove = now
        end
        return 
    end

    -- 2. ДОДЖ СТРЕЛ
    local linears = {}
    if LinearProjectiles and LinearProjectiles.GetAll then
        linears = LinearProjectiles.GetAll()
    end
    
    local closestProj = nil
    local closestDist = 99999
    local closestProjDir = nil
    
    for _, proj in pairs(linears) do
        if proj and proj.position and proj.velocity then
            local projPos = proj.position
            local distToProj = GetDistanceSafe(myPos, projPos)
            
            if distToProj < 1500 and distToProj < closestDist then
                local vel = proj.velocity
                if vel and (vel.x ~= 0 or vel.y ~= 0) then
                    local dirToHero = (myPos - projPos):Normalized()
                    local projDir = Vector(vel.x, vel.y, 0):Normalized()
                    local dot = dirToHero:Dot(projDir)
                    
                    if dot > 0 then
                        closestDist = distToProj
                        closestProj = projPos
                        closestProjDir = projDir
                    end
                end
            end
        end
    end
    
    if closestProj and closestProjDir then
        local perpDir = Vector(-closestProjDir.y, closestProjDir.x, 0):Normalized()
        local dodgeDist = 65
        local dodgeSide = 1
        perpDir = perpDir * dodgeSide
        local targetPos = myPos + perpDir * dodgeDist
        
        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
        return
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
    local minDist = 600
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

                if not bestTarget and dist < 600 then
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
        GlobalPhase = 8
        return
    end

    -- ПРИОРИТЕТ АТАКИ вне маршрутной фазы
    if bestTarget and finalPathState ~= 0 then
        local distToTarget = GetDistanceSafe(myPos, Entity.GetAbsOrigin(bestTarget))
        local standoff = GetAttackStandoff(h)
        
        if distToTarget > standoff then
            -- Подходим на дистанцию атаки
            local attackPos = myPos + (Entity.GetAbsOrigin(bestTarget) - myPos):Normalized() * (distToTarget - standoff)
            if now - lastMove >= 0.35 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, attackPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            -- Уже на дистанции атаки - бьем
            if now - lastMove >= 0.35 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                lastMove = now
            end
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
        local wpPos = WAYPOINTS[currentWaypoint]
        local distToWp = GetDistanceSafe(myPos, wpPos)
        local isStash = STASH_WPS[currentWaypoint]

        -- ТОЛЬКО если ключ был поднят в нычке: сразу дропаем топорик на землю.
        if dropAxeAfterStashKey and keyInInv and (now - lastAxeDropTime) >= 0.25 then
            local axeItem = FindAxeForDrop(h)
            lastAxeDropTime = now

            if axeItem then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, axeItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                dropAxeAfterStashKey = false
                return
            end

            -- Топорика нет: завершаем одноразовый сценарий, чтобы не зациклиться.
            dropAxeAfterStashKey = false
        end

        -- Пока рядом есть враги, не двигаем прогрессию маршрута: сначала зачищаем локальную область.
        local nearbyEnemy, nearbyEnemyDist = FindNearestCombatEnemy(h, myPos, 500, all_npcs)
        if nearbyEnemy then
            local enemyPos = Entity.GetAbsOrigin(nearbyEnemy)
            local standoff = GetAttackStandoff(h)

            if enemyPos and nearbyEnemyDist > standoff then
                local approachPos = myPos + (enemyPos - myPos):Normalized() * (nearbyEnemyDist - standoff)
                if now - lastMove >= 0.3 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, approachPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if now - lastMove >= 0.25 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, nearbyEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                    lastMove = now
                end
            end
            return
        end

        local enemyNearWp, _ = FindNearestCombatEnemy(h, wpPos, 400, all_npcs)
        local mustClearBeforeMove = enemyNearWp ~= nil

        -- На маршруте сначала бьем врагов по линии движения и только потом наступаем на вейпоинт.
        local pathTarget = FindPathTarget(h, myPos, wpPos, all_npcs)
        if pathTarget then
            local targetPos = Entity.GetAbsOrigin(pathTarget)
            local distToTarget = GetDistanceSafe(myPos, targetPos)
            local standoff = GetAttackStandoff(h)

            if distToTarget > standoff then
                local approachPos = myPos + (targetPos - myPos):Normalized() * (distToTarget - standoff)
                if now - lastMove >= 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, approachPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if now - lastMove >= 0.3 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, pathTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                    lastMove = now
                end
            end
            return
        end

        -- Если у целевого вейпоинта есть враг, но он не попал в pathTarget,
        -- все равно идем/бьем его, чтобы не зависать на месте с блокировкой движения.
        if mustClearBeforeMove and enemyNearWp then
            local enemyPos = Entity.GetAbsOrigin(enemyNearWp)
            local standoff = GetAttackStandoff(h)
            local distToEnemy = enemyPos and GetDistanceSafe(myPos, enemyPos) or 0

            if enemyPos and distToEnemy > standoff then
                local approachPos = myPos + (enemyPos - myPos):Normalized() * (distToEnemy - standoff)
                if now - lastMove >= 0.3 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, approachPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if now - lastMove >= 0.25 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, enemyNearWp, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                    lastMove = now
                end
            end
            return
        end

        -- Если это нычка и есть ключ - пропускаем
        if keyInInv and isStash then
            if distToWp < 600 and not mustClearBeforeMove then 
                currentWaypoint = currentWaypoint + 1
                isWaitingInStash = false
                stashArriveTime = 0
                return
            end
        end

        -- Входим в логику нычки
        if isStash and distToWp < 550 then
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
            local stashEnemy, _ = FindNearestCombatEnemy(h, myPos, 400, all_npcs)
            if stashEnemy then
                local stashEnemyPos = Entity.GetAbsOrigin(stashEnemy)
                local standoff = GetAttackStandoff(h)
                local distToEnemy = stashEnemyPos and GetDistanceSafe(myPos, stashEnemyPos) or 0

                if stashEnemyPos and distToEnemy > standoff then
                    local approachPos = myPos + (stashEnemyPos - myPos):Normalized() * (distToEnemy - standoff)
                    if now - lastMove >= 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, approachPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMove = now
                    end
                else
                    if now - lastMove >= 0.25 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, stashEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
                        lastMove = now
                    end
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

        local arrivalDist = 180

        if distToWp < arrivalDist and not mustClearBeforeMove then
            isWaitingInStash = false
            stashArriveTime = 0
            if currentWaypoint == #WAYPOINTS then
                if keyInInv then finalPathState = 1 else currentWaypoint = 1 end
            else 
                currentWaypoint = currentWaypoint + 1 
            end
        elseif not mustClearBeforeMove and now - lastMove >= 0.5 then
            -- Антиосцилляция: не спамим move если уже идём к тому же вейпоинту и дистанция уменьшается
            local curDist = distToWp
            if lastMoveTarget == currentWaypoint and curDist < lastMoveTargetDist and (lastMoveTargetDist - curDist) > 5 then
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
        
        if GetDistanceSafe(myPos, BOSS_POS) > 250 then
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

return script
