local script = {}

-- НОВЫЕ ДАННЫЕ ИЗ ТВОЕГО ЗАПРОСА
local TARGET_ITEM_NAME = "item_gem_shard" 
local QUICKBUY_NAME = "gem_shard"          
local SHOP_POS = Vector(-12952, -2939, 640)
local MOON_SHARD_NAME = "dark_moon_shard"
local MOON_SHARD_COUNT = 6
local LICH_HEART = "item_lich_heart"

-- Новые таргеты
local TARGET_NPCS = {
    "npc_dota_zone_3_unit_1",
    "npc_dota_zone_3_unit_2",
    "npc_dota_zone_3_unit_3"
}

local PROTECTED_KEYWORDS = {
    "crit_blade", 
    "book_of_knowledge", 
    "universal", 
    "doom_sword", 
    "doom_spear", 
    "dark_moon_shard", 
    "bfury",
    "quelling"
}

-- Новая плита
local PLATE_POS = Vector(-11297, 4474, 1024) 

-- Новые вейпоинты
local WAYPOINTS = {
    Vector(-13667, -2269, 640), 
    Vector(-14340, -1649, 768), 
    Vector(-14639, -948, 640),
    Vector(-15161, -610, 768), 
    Vector(-15637, -1554, 640), 
    Vector(-15426, -2342, 755),
    Vector(-15538, 727, 876), 
    Vector(-14880, 1184, 896), 
    Vector(-14688, 2336, 896),
    Vector(-15489, 2202, 1024), 
    Vector(-13600, 1888, 896), 
    Vector(-14240, 2976, 896),
    Vector(-13024, 1269, 768), 
    Vector(-12157, 2068, 896), 
    Vector(-11949, 2924, 896),
    Vector(-11711, 3521, 896), 
    Vector(-11801, 4605, 1011)
}

-- Новые точки выпуска овец
local SHEEP_RELEASE_POINTS = {
    Vector(-15759, -2870, 896), 
    Vector(-15771, 2932, 1152), 
    Vector(-11357, 2057, 1152)  
}

-- Координаты и имя нового Босса
local BOSS_POS = Vector(-14143, 5457, 1152)
local BOSS_NAME = "npc_dota_boss_lich"

-- Состояния скрипта
local currentWaypoint = 1
local releaseIndex = 1
local lastMove = 0
local moveDelay = 0.35
local lastActionTime = 0
local buyStep = 0 
local moonShardPurchased = 0
local item_to_return = nil
local was_moved = false
local was_used = false
local huntBoss = false 
local pickingHeart = false
local onPlateStep = false

local function Hero() 
    return Heroes.GetLocal() 
end

local function PlayerMe()
    local h = Hero()
    if not h then return nil end
    for _, p in ipairs(Players.GetAll()) do
        if Player.GetAssignedHero(p) == h then 
            return p 
        end
    end
end

local function IsProtected(itemName)
    if not itemName then return false end
    itemName = itemName:lower()
    for _, key in ipairs(PROTECTED_KEYWORDS) do
        if itemName:find(key) then 
            return true 
        end
    end
    return false
end

-- Проверка, является ли NPC таргетом из списка
local function IsTargetUnit(npc)
    if not npc then return false end
    local name = NPC.GetUnitName(npc)
    for _, target in ipairs(TARGET_NPCS) do
        if name == target then return true end
    end
    -- Также оставляем проверку по скиллам, как было в старом скрипте
    for i = 0, 15 do 
        local ability = NPC.GetAbilityByIndex(npc, i)
        if ability then
            local n = Ability.GetName(ability):lower()
            if n:find("tusk_") or n:find("crystal_maiden") or n:find("ancient_apparition") or n:find("glimmer") then
                return true
            end
        end
    end
    return false
end

-- Проверка нахождения рядом с точкой выпуска овец (радиус 300)
local function IsNearForbiddenSheepPoint(pos)
    if not pos then return false end
    -- Пока не пройдены все вейпоинты, нельзя подходить к точкам выпуска
    if currentWaypoint <= #WAYPOINTS then
        for _, relPos in ipairs(SHEEP_RELEASE_POINTS) do
            if (pos - relPos):Length2D() < 300 then
                return true
            end
        end
    end
    return false
end

function script.OnUpdate()
   
    local h = Hero()
    if not h or not Entity.IsAlive(h) then 
        return 
    end

    local pMe = PlayerMe()
    if not pMe then 
        return 
    end

    local myPos = Entity.GetAbsOrigin(h)
    local now = os.clock()

    -- ЗАПРЕТ ПОДХОДА К ТОЧКАМ ОВЕЦ, ПОКА ИДЕТ ПАТРУЛЬ
    if currentWaypoint <= #WAYPOINTS and not huntBoss and not pickingHeart and not onPlateStep and IsNearForbiddenSheepPoint(myPos) then
        if now - lastMove >= moveDelay then
            -- Отходим к первому вейпоинту, если забрели в радиус 300 к овцам
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, WAYPOINTS[1], nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastMove = now
        end
        return
    end

    -- ЛОГИКА ЗАКУПКИ
    if buyStep < 6 then
        if buyStep == 0 then
            if (myPos - SHOP_POS):Length2D() > 150 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, SHOP_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else 
                buyStep = 0.5 
                lastActionTime = now 
            end
        elseif buyStep == 0.5 then
            if now - lastActionTime >= 0.5 then 
                Engine.ExecuteCommand("dota_clear_quickbuy") 
                Engine.SetQuickBuy(MOON_SHARD_NAME, true) 
                buyStep = 1 
                lastActionTime = now 
            end
        elseif buyStep == 1 then
            if now - lastActionTime >= 0.9 then
                if moonShardPurchased < MOON_SHARD_COUNT then
                    Engine.ExecuteCommand("dota_purchase_quickbuy")
                    moonShardPurchased = moonShardPurchased + 1
                    lastActionTime = now
                else 
                    buyStep = 1.5 
                    lastActionTime = now 
                end
            end
        elseif buyStep == 1.5 then
            if now - lastActionTime >= 0.5 then 
                Engine.SetQuickBuy(QUICKBUY_NAME, true) 
                buyStep = 2 
                lastActionTime = now 
            end
        elseif buyStep == 2 then
            if now - lastActionTime >= 0.9 then 
                Engine.ExecuteCommand("dota_purchase_quickbuy") 
                buyStep = 3 
                lastActionTime = now 
            end
        elseif buyStep == 3 then
            if now - lastActionTime < 1.0 then return end
            for i = 0, 8 do
                local it = NPC.GetItemByIndex(h, i)
                if it and Ability.GetName(it) == TARGET_ITEM_NAME then
                    if i ~= 0 then 
                        item_to_return = NPC.GetItemByIndex(h, 0)
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), it, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    end
                    was_moved = true 
                    buyStep = 4 
                    lastActionTime = now 
                    return
                end
            end
        elseif buyStep == 4 then
            if now - lastActionTime < 1.0 then return end
            local shard = nil
            for i = 0, 5 do 
                local it = NPC.GetItemByIndex(h, i) 
                if it and Ability.GetName(it) == TARGET_ITEM_NAME then 
                    shard = it 
                    break 
                end 
            end
            if shard then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                was_used = true 
                lastActionTime = now
            elseif was_used or not shard then 
                buyStep = 5 
            end
        elseif buyStep == 5 then
            if was_moved and item_to_return then 
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), item_to_return, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h) 
            end
            buyStep = 6 
        end
        return
    end

    -- ПОИСК ВРАГОВ
    local all_npcs = NPCs.GetAll()
    local bestTarget = nil
    local bossVisible = nil
    local minDist = 1200 

    for i = 1, #all_npcs do
        local e = all_npcs[i]
        if Entity.IsAlive(e) and not Entity.IsSameTeam(h, e) and not Entity.IsDormant(e) then
            local eName = NPC.GetUnitName(e)
            local ePos = Entity.GetAbsOrigin(e)
            local dist = (myPos - ePos):Length2D()
            
            if eName == BOSS_NAME then 
                bossVisible = e 
            end
            
            if IsTargetUnit(e) then
                if dist < minDist then 
                    minDist = dist 
                    bestTarget = e 
                end
            end
        end
    end

    -- АТАКА
    if bestTarget then
        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
        return
    end

    -- ПОСЛЕ ЗАВЕРШЕНИЯ ВЕЙПОИНТОВ ИЛИ ПРИ ОСОБЫХ ШАГАХ
    if currentWaypoint > #WAYPOINTS or huntBoss or pickingHeart or onPlateStep then
        
        -- Проверка Сердца Лича
        local heartHandle = nil
        local heartSlot = -1
        for i = 0, 8 do
            local it = NPC.GetItemByIndex(h, i)
            if it and Ability.GetName(it) == LICH_HEART then 
                heartHandle = it 
                heartSlot = i 
                break 
            end
        end

        if heartHandle then
            if heartSlot > 5 then
                local emptySlot = -1
                for i = 0, 5 do 
                    if not NPC.GetItemByIndex(h, i) then 
                        emptySlot = i 
                        break 
                    end 
                end
                if emptySlot ~= -1 then
                    if now - lastActionTime >= 0.8 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, emptySlot, Vector(0,0,0), heartHandle, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastActionTime = now
                    end
                else
                    for i = 0, 5 do
                        local it = NPC.GetItemByIndex(h, i)
                        if it and not IsProtected(Ability.GetName(it)) then
                            if now - lastActionTime >= 0.8 then
                                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, it, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                                lastActionTime = now
                            end
                            return
                        end
                    end
                end
            else
                _G.GlobalPhase = 4 
                return
            end
            return
        end

        if pickingHeart then
            local mapItems = PhysicalItems.GetAll()
            for _, item in ipairs(mapItems) do
                local d = PhysicalItem.GetItem(item)
                if d and Ability.GetName(d) == LICH_HEART then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, item, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    return
                end
            end
        end

        -- ПЛИТА
        if onPlateStep then
            local distToPlate = (myPos - PLATE_POS):Length2D()
            if distToPlate > 50 then
                if now - lastMove >= 0.15 then 
                    local cutter = nil
                    for i = 0, 8 do
                        local it = NPC.GetItemByIndex(h, i)
                        if it then
                            local name = Ability.GetName(it):lower()
                            if name:find("quelling") or name:find("bfury") or name:find("battlefury") then
                                cutter = it
                                break
                            end
                        end
                    end
                    
                    local trees = Trees.InRadius(myPos, 380, true)
                    local bestTree = nil
                    local minTreeDist = 999
                    local dirToPlate = (PLATE_POS - myPos):Normalized()

                    for _, tree in ipairs(trees) do
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

                    if cutter and Ability.IsReady(cutter) and bestTree then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, bestTree, Vector(0,0,0), cutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastActionTime = now
                    else
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, PLATE_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    end
                    lastMove = now
                end
            else
                onPlateStep = false
            end
            return
        end

        -- ОХОТА НА БОССА
        if huntBoss then
            if bossVisible then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bossVisible, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            else
                if (myPos - BOSS_POS):Length2D() > 200 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, BOSS_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                else 
                    pickingHeart = true 
                    huntBoss = false 
                end
            end
            return
        end

        -- ВЫПУСК ОВЕЦ (ПО ОЧЕРЕДИ)
        local relPos = SHEEP_RELEASE_POINTS[releaseIndex]
        if relPos then
            local dist = (myPos - relPos):Length2D()
            
            if dist < 700 then
                local ult = NPC.GetAbilityByIndex(h, 5)
                if ult and Ability.IsReady(ult) and Ability.IsCastable(ult, NPC.GetMana(h)) then
                    if now - lastActionTime > 0.5 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), ult, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastActionTime = now
                    end
                end
            end

            if dist > 100 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, relPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if releaseIndex == 1 then 
                    onPlateStep = true 
                end 
                releaseIndex = releaseIndex + 1
                if releaseIndex > #SHEEP_RELEASE_POINTS then 
                    huntBoss = true 
                end
            end
            return
        end
    end

    -- ОСНОВНОЙ ПАТРУЛЬ (ВЕЙПОИНТЫ)
    if currentWaypoint <= #WAYPOINTS then
        local wp = WAYPOINTS[currentWaypoint]
        if (myPos - wp):Length2D() > 200 then
            if now - lastMove >= moveDelay then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wp, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            currentWaypoint = currentWaypoint + 1
        end
    end
end

return script