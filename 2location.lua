local script = {}

-- Настройки целей Локация 2
local TARGET_UNITS = {
    ["npc_dota_zone_2_unit_2"] = true,
    ["npc_dota_zone_2_unit_3"] = true,
    ["npc_dota_zone_2_unit_1"] = true,
    ["npc_dota_zone_2_unit_4"] = true
}
local CRATE_NAME = "npc_dota_crate"
local BOSS_NAME = "npc_dota_boss_undying"

-- Вейпоинты Локация 2
local WAYPOINTS_L2 = {
    Vector(-11002, -10304, 512), Vector(-10434, -10059, 512), Vector(-9184, -10156, 512),
    Vector(-8327, -10081, 512), Vector(-7598, -9371, 512), Vector(-8698, -8854, 512),
    Vector(-7591, -8625, 512), Vector(-7271, -8665, 512), Vector(-9169, -8417, 512), Vector(-8163, -7628, 512), Vector(-8712, -6994, 512),
    Vector(-9806, -5593, 512), Vector(-10616, -5822, 512), Vector(-11810, -5379, 512),
    Vector(-12805, -5235, 512), Vector(-11910, -6782, 512), Vector(-12893, -7878, 384),
    Vector(-13827, -7388, 384), Vector(-14352, -4895, 384), Vector(-15090, -6866, 384),
    Vector(-15256, -5172, 384), Vector(-15533, -7794, 384), 
    Vector(-15552, -8385, 512), Vector(-10962, -8312, 512),
    Vector(-10036, -7284, 512), -- 24
    Vector(-8277, -4899, 384)   -- 26 (Босс)
}

local PLATE_POS = Vector(-14006, -4138, 512)
local PLATE_WP = 15

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

local function IsMedusa(h)
    return h and NPC.GetUnitName(h) == "npc_dota_hero_medusa"
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

local function EstimateMedusaWaypoint(medusaPos)
    if not medusaPos then return #WAYPOINTS_L2 + 1 end
    local bestIdx = 1
    local bestDist = 999999
    for i = 1, #WAYPOINTS_L2 do
        local d = (medusaPos - WAYPOINTS_L2[i]):Length2D()
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
    end
    if bestDist < 250 then return bestIdx + 1 end
    return bestIdx
end

local currentWP = 1
local lastMoveTime = 0
local bossWasSeen = false
local lastTreeCut = 0
local plateDone = false
local onPlateStep = false

local function FindCutterItem(hero)
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(hero, i)
        if it then
            local name = (Ability.GetName(it) or ""):lower()
            if name:find("quelling") or name:find("bfury") or name:find("battlefury") then
                return it, i
            end
        end
    end
    return nil, -1
end

function script.OnUpdate()
    if _G.GlobalPhase ~= 2 then return end

    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end

    local myPlayer = Players.GetLocal()
    if not myPlayer then return end

    local myPos = Entity.GetAbsOrigin(myHero)
    local now = os.clock()

    local routeFinished = currentWP > #WAYPOINTS_L2
    local targetPos = WAYPOINTS_L2[math.min(currentWP, #WAYPOINTS_L2)]

    -- 1. ПОИСК ЦЕЛЕЙ
    local allNPCs = NPCs.GetAll()
    local crateTarget = nil
    local bossTarget = nil
    local normalTarget = nil

    local bossAliveNow = false
    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if npc and Entity.IsAlive(npc) and not Entity.IsSameTeam(myHero, npc) and not Entity.IsDormant(npc) then
            local npcPos = Entity.GetAbsOrigin(npc)
            local distToHero = (npcPos - myPos):Length2D()
            local name = NPC.GetUnitName(npc)

            -- Ящики всегда в приоритете, если вплотную
            if name == CRATE_NAME and distToHero <= 65 then
                crateTarget = npc
            end

            -- Если мы на финальной точке, ищем босса в большом радиусе (1000)
            if name == BOSS_NAME then
                bossWasSeen = true
                bossAliveNow = true
                local bossSearchDist = (routeFinished or currentWP >= 24) and 1800 or 400
                if distToHero <= bossSearchDist then
                    bossTarget = npc
                end
            end

            -- Обычные мобы в радиусе 400
            if TARGET_UNITS[name] and distToHero <= 400 and not routeFinished then
                normalTarget = npc
            end
        end
    end

    if routeFinished and bossWasSeen and not bossAliveNow then
        _G.GlobalPhase = 3
        return
    end

    -- 2. ВЫБОР ЦЕЛИ (после окончания маршрута бьем только босса)
    local activeTarget = nil
    if routeFinished then
        activeTarget = bossTarget
    else
        activeTarget = crateTarget or bossTarget or normalTarget
    end

    if activeTarget then
        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, activeTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
        return
    end

    -- 2.5. ПЛИТА С РУБКОЙ ДЕРЕВЬЕВ
    if onPlateStep then
        local distToPlate = (myPos - PLATE_POS):Length2D()
        if distToPlate > 50 then
            -- Сначала убиваем врагов рядом
            local nearEnemy = nil
            for i = 1, #allNPCs do
                local npc = allNPCs[i]
                if npc and Entity.IsAlive(npc) and not Entity.IsSameTeam(myHero, npc) and not Entity.IsDormant(npc) then
                    local npcPos = Entity.GetAbsOrigin(npc)
                    local d = (npcPos - myPos):Length2D()
                    local name = NPC.GetUnitName(npc)
                    if d <= 500 and (TARGET_UNITS[name] or name == CRATE_NAME) then
                        nearEnemy = npc
                        break
                    end
                end
            end

            if nearEnemy then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, nearEnemy, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                return
            end

            if now - lastMoveTime >= 0.15 then
                local cutter, cSlot = FindCutterItem(myHero)
                local activeCutter = (cutter and cSlot <= 5) and cutter or nil

                local trees = Trees.InRadius(myPos, 380, true)
                local bestTree = nil
                local minTreeDist = 999
                local dirToPlate = (PLATE_POS - myPos):Normalized()

                for _, tree in pairs(trees) do
                    local treePos = Entity.GetAbsOrigin(tree)
                    local dirToTree = (treePos - myPos):Normalized()
                    local distToTree = (myPos - treePos):Length2D()
                    local dot = dirToTree:Dot(dirToPlate)
                    if dot > -0.17 then
                        if distToTree < minTreeDist then
                            minTreeDist = distToTree
                            bestTree = tree
                        end
                    end
                end

                if activeCutter and Ability.IsReady(activeCutter) and bestTree and (now - lastTreeCut >= 0.8) then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, Entity.GetIndex(bestTree), Vector(0,0,0), activeCutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    lastTreeCut = now
                else
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, PLATE_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                end
                lastMoveTime = now
            end
        else
            onPlateStep = false
            plateDone = true
        end
        return
    end

    -- 3. ДВИЖЕНИЕ
    -- Non-Medusa в команде: следует позади Медузы (75 юнитов назад)
    if HasTeammate() and not IsMedusa(myHero) then
        local medusa = FindTeammateMedusa()
        if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
            local medusaPos = Entity.GetAbsOrigin(medusa)
            local dir = (targetPos - medusaPos):Normalized()
            local behindPos = medusaPos - dir * 75
            local distToBehind = (myPos - behindPos):Length2D()
            if distToBehind > 50 and now - lastMoveTime > 0.3 then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, behindPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                lastMoveTime = now
            end
            local medusaWP = EstimateMedusaWaypoint(medusaPos)
            if medusaWP > 0 then currentWP = math.max(1, medusaWP) end
            return
        end
    end

    local distToWP = (myPos - targetPos):Length2D()

    if distToWP > 100 then
        if now - lastMoveTime > 0.3 then
            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
            lastMoveTime = now
        end
    else
        -- При достижении WP19 запускаем плиту
        if currentWP == PLATE_WP and not plateDone then
            onPlateStep = true
            return
        end
        -- Non-Medusa не может обогнать Медузу по вейпоинтам
        if HasTeammate() and not IsMedusa(myHero) then
            local medusa = FindTeammateMedusa()
            if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                local medusaPos = Entity.GetAbsOrigin(medusa)
                local medusaWP = EstimateMedusaWaypoint(medusaPos)
                if currentWP + 1 > medusaWP then
                    return
                end
            end
        end
        currentWP = currentWP + 1
    end
end

return script