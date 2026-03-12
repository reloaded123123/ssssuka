local script = {}
-- пасхалка: ШАМИЛЬ ГЕЙ!
-- === НАСТРОЙКИ И КОНСТАНТЫ ===
script.target_names = { "npc_dota_zone_6_unit_3", "npc_dota_zone_6_unit_1", "npc_dota_zone_6_unit_2", "npc_dota_zone_6_unit_4" }
script.BOSS_NAME = "npc_dota_boss_slardar"
script.KNIFE_NAME = "battlemage"
script.BOSS_SKILL_NAME = "torrential_waters"
script.item_to_pick = "item_naga_stone"
script.BOSS_SOUL_NAME = "item_boss_soul"
script.MOON_SHARD_NAME = "item_moon_shard"

script.START_POS = Vector(-5766, 3272, 384)
script.OUTPOST_2_POS = Vector(-3772, 3677, 384) 
script.PRE_BOSS_POS = Vector(-4702, 2520, 128)  
script.BOSS_ENT_POS = Vector(-4640, -5892, 128)
script.BOSS_FINAL_POS = Vector(-4684, -6619, 128)

script.waypoints = {
    Vector(-5068, 1863, 384),
    Vector(-5402, 1278, 384),
    Vector(-4456, 947, 384),
    Vector(-3480, 1127, 384),
    Vector(-2430, 957, 384),
    Vector(-1957, 155, 384),
    Vector(-2402, -585, 384),
    Vector(-1643, -1236, 512),
    Vector(-2033, -1598, 392),
    Vector(-3038, -1515, 384),
    Vector(-3652, -1056, 384),
    Vector(-3981, -347, 384),
    Vector(-4764, -813, 384),
    Vector(-5859, -1176, 384),
    Vector(-5529, -2163, 384),
    Vector(-4851, -1929, 384),
    Vector(-5468, -3014, 611),
    Vector(-5306, -3111, 640),
    Vector(-4837, -3404, 640),
    Vector(-4248, -2928, 384),
    Vector(-3408, -2774, 512),
    Vector(-2719, -3401, 384),
    Vector(-2223, -4493, 495),
    Vector(-2664, -5358, 384),
    Vector(-3812, -5658, 384),
    Vector(-4713, -7116, 384)
}

-- === ПЕРЕМЕННЫЕ СОСТОЯНИЯ ===
script.state = "START_BUYING" 
script.currentWP = 1
script.lastActionTime = 0
script.lastMoveTime = 0
script.purchaseCount = 0
script.setupDone = false
script.item_to_return = nil
script.lastPos = Vector(0,0,0)
script.stuckTicks = 0
script.lastHealth = 0
script.waitStartTime = 0 
script.lastLoggedState = ""

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

local function GetKnives(h)
    if not h then return nil end
    for i = 0, 5 do
        local it = NPC.GetItemByIndex(h, i)
        if it then
            local itemName = Ability.GetName(it)
            if itemName:lower():find(script.KNIFE_NAME) then 
                return it 
            end
        end
    end
    return nil
end

function script.FindItemInInventory(hero, name)
    if not hero then return nil, -1 end
    for i = 0, 15 do
        local it = NPC.GetItemByIndex(hero, i)
        if it then
            if Ability.GetName(it) == name then 
                return it, i 
            end
        end
    end
    return nil, -1
end

function script.CountHeads(hero)
    if not hero then return 0 end
    local count = 0
    for i = 0, 15 do
        local it = NPC.GetItemByIndex(hero, i)
        if it then
            if Ability.GetName(it) == script.item_to_pick then
                count = count + Item.GetCurrentCharges(it)
            end
        end
    end
    return count
end

function script.UseThirdAbility(hero, player, now)
    local abil = NPC.GetAbilityByIndex(hero, 2)
    if abil then
        if Ability.IsReady(abil) and Ability.IsCastable(abil, NPC.GetMana(hero)) then
            if now - script.lastActionTime > 0.1 then
                Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), abil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
                script.lastActionTime = now
                return true
            end
        end
    end
    return false
end

-- === ОСНОВНАЯ ЛОГИКА ОБНОВЛЕНИЯ ===

function script.OnUpdate()
    if _G.GlobalPhase ~= 6 then 
        return 
    end

    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then 
        return 
    end
    
    local myPlayer = Players.GetLocal()
    local myPos = Entity.GetAbsOrigin(myHero)
    local now = os.clock()

    if script.state ~= script.lastLoggedState then
        print("PHASE 6 STATE: " .. script.state)
        script.lastLoggedState = script.state
    end

    if NPC.HasModifier(myHero, "modifier_teleporting") then 
        return 
    end

    local headsCount = script.CountHeads(myHero)

    -- БЛОК 1: ЗАКУПКА MOON SHARD
    if script.state == "START_BUYING" then
        local distToStart = (myPos - script.START_POS):Length2D()
        
        if distToStart > 200 then
            if now - script.lastMoveTime > 0.8 then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.START_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                script.lastMoveTime = now
            end
        else
            local shard, s_slot = script.FindItemInInventory(myHero, script.MOON_SHARD_NAME)
            
            if shard then
                if now - script.lastActionTime > 1.2 then
                    if s_slot <= 5 then
                        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET, myHero, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                        script.lastActionTime = now
                    else
                        local freeSlot = -1
                        for i = 0, 5 do 
                            if not NPC.GetItemByIndex(myHero, i) then 
                                freeSlot = i 
                                break 
                            end 
                        end
                        
                        if freeSlot ~= -1 then
                            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, freeSlot, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                        else
                            script.item_to_return = NPC.GetItemByIndex(myHero, 0)
                            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                        end
                        script.lastActionTime = now
                    end
                end
                return
            end

            if not shard and script.item_to_return then
                if now - script.lastActionTime > 0.8 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), script.item_to_return, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    script.item_to_return = nil
                    script.lastActionTime = now
                end
                return
            end

            if not shard and not script.item_to_return then
                if script.purchaseCount < 4 then
                    if not script.setupDone then
                        Engine.ExecuteCommand("dota_clear_quickbuy")
                        Engine.SetQuickBuy("moon_shard", true)
                        script.setupDone = true
                    end
                    if now - script.lastActionTime > 1.0 then
                        Engine.ExecuteCommand("dota_purchase_quickbuy")
                        script.purchaseCount = script.purchaseCount + 1
                        script.lastActionTime = now
                    end
                else
                    script.state = "FARMING"
                end
            end
        end
        return
    end

    -- БЛОК 2: ТЕЛЕПОРТАЦИЯ И ПУТЬ К БОССУ
    if script.state == "TELEPORTING" then
        local distToOutpost = (myPos - script.OUTPOST_2_POS):Length2D()
        
        if distToOutpost < 150 then
            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
            script.state = "POST_TELEPORT_WAIT"
            script.waitStartTime = now
            return
        end

        if distToOutpost > 600 then
            local tp = script.FindItemInInventory(myHero, "item_tpscroll") or script.FindItemInInventory(myHero, "item_travel_boots")
            if tp and Ability.IsReady(tp) then
                if now - script.lastActionTime > 1.2 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, script.OUTPOST_2_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    script.lastActionTime = now
                end
            else
                if now - script.lastMoveTime > 0.8 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.OUTPOST_2_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    script.lastMoveTime = now
                end
            end
        else
            if now - script.lastMoveTime > 0.8 then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.OUTPOST_2_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                script.lastMoveTime = now
            end
        end
        return

    elseif script.state == "POST_TELEPORT_WAIT" then
        if now - script.waitStartTime > 1.0 then 
            script.state = "MOVE_TO_PRE_BOSS" 
        end
        return

    elseif script.state == "MOVE_TO_PRE_BOSS" then
        if (myPos - script.PRE_BOSS_POS):Length2D() > 150 then
            if now - script.lastMoveTime > 0.8 then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.PRE_BOSS_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                script.lastMoveTime = now
            end
        else 
            script.state = "TO_BOSS_ENTRANCE" 
        end
        return

    elseif script.state == "TO_BOSS_ENTRANCE" then
        if (myPos - script.BOSS_ENT_POS):Length2D() > 200 then
            if not script.CheckAndAttackNearby(myHero, myPlayer, now) then
                if now - script.lastMoveTime > 0.8 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.BOSS_ENT_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    script.lastMoveTime = now
                end
            end
        else 
            script.state = "BOSS_FIGHT" 
        end
        return

    -- БЛОК 3: ФАЗА БИТВЫ С БОССОМ
    elseif script.state == "BOSS_FIGHT" then
        local soul, _ = script.FindItemInInventory(myHero, script.BOSS_SOUL_NAME)
        if soul then
            _G.GlobalPhase = 7
            return
        end

        -- Подбор души или камней во время боя
        local dropped = PhysicalItems.GetAll()
        for i = 1, #dropped do
            local pItem = dropped[i]
            if pItem and not Entity.IsDormant(pItem) then
                if (Entity.GetAbsOrigin(pItem) - myPos):Length2D() < 800 then
                    local itEnt = PhysicalItem.GetItem(pItem)
                    if itEnt then
                        local n = Ability.GetName(itEnt)
                        if n == script.BOSS_SOUL_NAME or n == script.item_to_pick then
                            if now - script.lastActionTime > 0.5 then
                                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pItem, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                                script.lastActionTime = now
                                return 
                            end
                        end
                    end
                end
            end
        end

        -- Поиск босса
        local boss = nil
        local enemies = Entity.GetUnitsInRadius(myHero, 1500, Enum.TeamType.TEAM_ENEMY)
        for i = 1, #enemies do
            local en = enemies[i]
            if en and Entity.IsAlive(en) then
                if NPC.GetUnitName(en) == script.BOSS_NAME then
                    boss = en
                    break
                end
            end
        end

        if boss then
            local kn = GetKnives(myHero)
            if kn and Ability.IsReady(kn) then 
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), kn, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero) 
            end
            
            script.UseThirdAbility(myHero, myPlayer, now)

            if now - script.lastActionTime > 0.5 then
                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, boss, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                script.lastActionTime = now
            end
        else
            if (myPos - script.BOSS_FINAL_POS):Length2D() > 100 then
                if now - script.lastMoveTime > 0.8 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, script.BOSS_FINAL_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    script.lastMoveTime = now
                end
            end
            -- Если босса нет и есть 4 головы, можем вернуться в фарм (или ждать)
            if headsCount >= 4 and not boss then 
                script.state = "FARMING" 
            end
        end
        return
    end

    -- БЛОК 4: ФАРМ И ПЕРЕДВИЖЕНИЕ ПО КАРТЕ
    if script.state == "FARMING" then
        
        -- Проверка на застревание
        if (myPos - script.lastPos):Length2D() < 15 then
            script.stuckTicks = script.stuckTicks + 1
            if script.stuckTicks > 40 then
                script.currentWP = script.currentWP + 1
                if script.currentWP > #script.waypoints then script.currentWP = 1 end
                script.stuckTicks = 0
            end
        else 
            script.stuckTicks = 0 
        end
        script.lastPos = myPos

        -- Поиск предметов для подбора (не блокирует движение)
        if headsCount < 30 then 
            local pItems = PhysicalItems.GetAll()
            for i = 1, #pItems do
                local pi = pItems[i]
                if pi and not Entity.IsDormant(pi) then
                    local itEnt = PhysicalItem.GetItem(pi)
                    if itEnt and Ability.GetName(itEnt) == script.item_to_pick then
                        local dist = (Entity.GetAbsOrigin(pi) - myPos):Length2D()
                        if dist < 600 then
                            if now - script.lastActionTime > 0.6 then
                                Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pi, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                                script.lastActionTime = now
                                -- Важно: не возвращаем return, чтобы бот продолжал логику боя
                            end
                        end
                    end
                end
            end
        end

        -- Переход к следующей фазе (Телепорт), если собрано 30 голов
        if headsCount >= 30 then 
            local enemiesNear = Entity.GetUnitsInRadius(myHero, 750, Enum.TeamType.TEAM_ENEMY)
            local hasLivingEnemy = false
            for i = 1, #enemiesNear do
                if enemiesNear[i] and Entity.IsAlive(enemiesNear[i]) then 
                    hasLivingEnemy = true 
                    break 
                end
            end
            
            if not hasLivingEnemy then 
                script.state = "TELEPORTING" 
                return
            end
        end

        -- Выполнение боевой логики
        script.DoCombatLogic(myHero, myPlayer, now)
    end
end

-- === ФУНКЦИИ БОЯ И ДВИЖЕНИЯ ===

function script.CheckAndAttackNearby(hero, player, now)
    local enemies = Entity.GetUnitsInRadius(hero, 500, Enum.TeamType.TEAM_ENEMY)
    for i = 1, #enemies do
        local e = enemies[i]
        if e and Entity.IsAlive(e) then
            script.UseThirdAbility(hero, player, now)
            if now - script.lastActionTime > 0.6 then
                Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, e, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
                script.lastActionTime = now
            end
            return true
        end
    end
    return false
end

function script.DoCombatLogic(hero, player, now)
    local myPos = Entity.GetAbsOrigin(hero)
    local enemies = Entity.GetUnitsInRadius(hero, 900, Enum.TeamType.TEAM_ENEMY)
    local target = nil
    local count500 = 0
    local closestAny = nil
    local minDist = 9999
    
    for i = 1, #enemies do
        local e = enemies[i]
        if e and Entity.IsAlive(e) then
            local dist = (Entity.GetAbsOrigin(e) - myPos):Length2D()
            if dist < 500 then 
                count500 = count500 + 1 
            end
            if dist < minDist then 
                minDist = dist 
                closestAny = e 
            end
        end
    end

    -- Если врагов слишком много, фокусим ближайшего
    if count500 >= 8 and closestAny then 
        target = closestAny
    else
        -- Иначе ищем цели по списку приоритетов
        local hasMiss = NPC.HasModifier(hero, "modifier_blob_die_spawn_effect")
        if not hasMiss then
            for i = 1, #enemies do
                local e = enemies[i]
                if e and Entity.IsAlive(e) then
                    local name = NPC.GetUnitName(e)
                    local isValid = false
                    for j = 1, #script.target_names do
                        if name == script.target_names[j] then
                            isValid = true
                            break
                        end
                    end
                    if isValid then
                        target = e
                        break
                    end
                end
            end
        end
    end

    -- Атака цели
    if target then
        script.UseThirdAbility(hero, player, now)
        
        -- Прожатие ножей в бою
        local kn = GetKnives(hero)
        if kn and Ability.IsReady(kn) then
            Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), kn, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
        end

        if now - script.lastActionTime > 0.6 then
            Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, target, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
            script.lastActionTime = now
        end
    else
        -- Если целей нет — идем по маршруту
        local wp = script.waypoints[script.currentWP]
        local distToWp = (myPos - wp):Length2D()
        
        if distToWp < 200 then
            script.currentWP = script.currentWP + 1
            if script.currentWP > #script.waypoints then 
                script.currentWP = 1 
            end
        end
        
        if now - script.lastMoveTime > 0.7 then
            Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wp, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
            script.lastMoveTime = now
        end
    end
end

return script