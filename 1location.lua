local script = {}

-- Настройки целей
local QUEST_UNIT = "npc_dota_zone_1_unit_quest"
local ITEM_TO_PICK = "item_quelling_blade" -- Название предмета для поиска
local OTHER_UNITS = {
    ["npc_dota_zone_1_unit_1"] = true,
    ["npc_dota_zone_1_unit_2"] = true,
    ["npc_dota_zone_1_unit_3"] = true,
    ["npc_dota_zone_1_unit_4"] = true,
    ["npc_dota_zone_1_unit_5"] = true,
    ["npc_dota_zone_1_unit_6"] = true,
    ["npc_dota_boss_minion_ursa"] = true 
}
local BOSS_NAME = "npc_dota_boss_ursa"
local AGGRO_RADIUS = 400
local CHASE_RADIUS = 900
local BOSS_WP_INDEX = 23
local MINION_WP_INDEX = 24

-- Твои вейпоинты
local WAYPOINTS = {
    Vector(-13520, -14901, 462), Vector(-12753, -15254, 384), Vector(-12179, -14782, 512),
    Vector(-11716, -15300, 384), Vector(-10951, -15635, 512), Vector(-9681, -15429, 512),
    Vector(-8576, -15688, 384), Vector(-7748, -15189, 512), Vector(-8073, -14693, 435),
    Vector(-8294, -13775, 512), Vector(-8351, -12984, 512), Vector(-9313, -12423, 640),
    Vector(-8295, -11974, 640), Vector(-7437, -12970, 640), Vector(-9654, -13303, 512),
    Vector(-9784, -13968, 512), Vector(-10308, -14249, 512), Vector(-10902, -14663, 512),
    Vector(-11483, -14052, 384), Vector(-11259, -13364, 384), Vector(-10922, -12671, 256),
    Vector(-12377, -13102, 384), 
    Vector(-12432, -11892, 512), -- 23 (Босс)
    Vector(-11541, -11240, 512)  -- 24 (Подсосы)
}

local currentWP = 1
local killedQuestCount = 0
local lastQuestTarget = nil
local lastMoveTime = 0
local lastPickTime = 0
local lockedTarget = nil
local lockedTargetName = nil
local bossKilled = false

local function IsValidEnemy(myHero, npc)
    return npc and Entity.IsAlive(npc) and not Entity.IsDormant(npc) and not Entity.IsSameTeam(myHero, npc)
end

local function CanChaseTarget(myPos, npc)
    if not npc then return false end
    local npcPos = Entity.GetAbsOrigin(npc)
    if not npcPos then return false end
    return (npcPos - myPos):Length2D() <= CHASE_RADIUS
end

function script.OnUpdate()
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end

    local myPlayer = Players.GetLocal()
    if not myPlayer then return end

    local myPos = Entity.GetAbsOrigin(myHero)
    local now = os.clock()

    if currentWP > #WAYPOINTS then return end

    -- 0. ПОИСК ПРЕДМЕТА НА ЗЕМЛЕ (Приоритет выше атаки)
    local physicalItems = PhysicalItems.GetAll()
    for i = 1, #physicalItems do
        local pItem = physicalItems[i]
        if pItem and not Entity.IsDormant(pItem) then
            local itemEntity = PhysicalItem.GetItem(pItem)
            if itemEntity then
                local itemName = Ability.GetName(itemEntity)
                local itemPos = Entity.GetAbsOrigin(pItem)
                local distToItem = (itemPos - myPos):Length2D()

                -- Если нашли нужный предмет в радиусе 600
                if itemName == ITEM_TO_PICK and distToItem < 600 then
                    if now - lastPickTime > 0.5 then
                        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pItem, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                        lastPickTime = now
                    end
                    return -- Прерываем всё остальное, пока не подберем
                end
            end
        end
    end

    -- 1. ПОИСК ЦЕЛЕЙ В РАДИУСЕ 400 ОТ ГЕРОЯ
    local allNPCs = NPCs.GetAll()
    local questTarget = nil
    local normalTarget = nil
    local bossTarget = nil
    local bossLock = currentWP >= BOSS_WP_INDEX and not bossKilled

    -- 1.1 Если уже выбрана цель, продолжаем добивать ее, даже если она чуть отбежала.
    if lockedTarget then
        if IsValidEnemy(myHero, lockedTarget) and CanChaseTarget(myPos, lockedTarget) then
            local lockedName = NPC.GetUnitName(lockedTarget)
            if (not bossLock) or lockedName == BOSS_NAME then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, lockedTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                return
            end
        end

        if lockedTargetName == QUEST_UNIT and not Entity.IsAlive(lockedTarget) then
            killedQuestCount = killedQuestCount + 1
            print("Квестовых убито: " .. killedQuestCount .. "/11")
        elseif lockedTargetName == BOSS_NAME and not Entity.IsAlive(lockedTarget) then
            bossKilled = true
            print("Босс убит. Теперь можно добивать подсосов.")
        end

        lockedTarget = nil
        lockedTargetName = nil
    end

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if npc and Entity.IsAlive(npc) and not Entity.IsSameTeam(myHero, npc) and not Entity.IsDormant(npc) then
            local npcPos = Entity.GetAbsOrigin(npc)
            local distToHero = (npcPos - myPos):Length2D()
            
            if distToHero <= AGGRO_RADIUS or (bossLock and NPC.GetUnitName(npc) == BOSS_NAME and distToHero <= CHASE_RADIUS) then
                local name = NPC.GetUnitName(npc)
                if name == QUEST_UNIT then
                    questTarget = npc
                elseif name == BOSS_NAME and killedQuestCount >= 11 and not bossKilled then
                    bossTarget = npc
                elseif OTHER_UNITS[name] and not bossLock then
                    normalTarget = npc
                end
            end
        end
    end

    -- 2. ВЫБОР АКТИВНОЙ ЦЕЛИ
    local activeTarget = nil
    if bossLock then
        if bossTarget then
            activeTarget = bossTarget
        end
    elseif questTarget then
        activeTarget = questTarget
        lastQuestTarget = questTarget
    elseif bossTarget then
        activeTarget = bossTarget
    elseif normalTarget then
        activeTarget = normalTarget
    end

    if activeTarget then
        lockedTarget = activeTarget
        lockedTargetName = NPC.GetUnitName(activeTarget)
        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, activeTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
        return
    end

    -- 3. СЧЕТЧИК КВЕСТОВЫХ
    if lastQuestTarget and not Entity.IsAlive(lastQuestTarget) then
        killedQuestCount = killedQuestCount + 1
        lastQuestTarget = nil
        print("Квестовых убито: " .. killedQuestCount .. "/11")
    end

    -- 4. ДВИЖЕНИЕ ПО ВЕЙПОИНТАМ
    local targetPos = WAYPOINTS[currentWP]

    -- На последних вейпоинтах сначала обязательно убиваем босса.
    if currentWP >= BOSS_WP_INDEX and not bossKilled then
        targetPos = WAYPOINTS[BOSS_WP_INDEX]
    end

    local distToWP = (myPos - targetPos):Length2D()

    if distToWP > 100 then
        if now - lastMoveTime > 0.3 then
            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
            lastMoveTime = now
        end
    else
        if currentWP == BOSS_WP_INDEX and not bossKilled then
            return
        end

        if currentWP == MINION_WP_INDEX and not bossKilled then
            currentWP = BOSS_WP_INDEX
            return
        end

        currentWP = currentWP + 1
        print("Вейпоинт достигнут: " .. (currentWP - 1) .. " -> Идем к " .. currentWP)
    end
end

return script