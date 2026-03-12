local module = {}

-- === КООРДИНАТЫ БЛОК 1 (ЛОВУШКИ И ИЛЛЮЗИИ) ===
local START_PLATE  = Vector(-12752, 14417, 384) 
local FINAL_TARGET = Vector(-10075, 14462, 384) 
local FINISH_ZONE  = Vector(-10976, 14432, 384) 
local LAST_TRIGGER = Vector(-11772, 14325, 640) 
local STAGE2_ENTRANCE = Vector(-10528, 14368, 384) 

-- ОДНА ТОЧКА ДЛЯ ФЛАСКИ
local FLASK_POINT   = Vector(-9884, 14336, 640)

local BOSS_ZONE     = Vector(-7005, 14457, 512)
local KEY_NAME      = "item_prison_cell_key"
local LICH_HEART    = "item_lich_heart"
local KEY_TARGET_1 = Vector(-3503, 15704, 256) 
local KEY_TARGET_2 = Vector(-4839, 15707, 256) 

-- ЛОГИКА ФЛАСКИ
local FLASK_TARGET_ITEMS = {
    "item_bkb_flask",
    "item_immune_flask"
}

local flaskLogic = {
    is_active = false,
    was_moved = false,
    was_used = false,
    move_time = 0,
    original_slot = -1,
    finished = false
}

-- Функция сброса логики фласки
local function ResetFlaskLogic()
    flaskLogic.is_active = false
    flaskLogic.was_moved = false
    flaskLogic.was_used = false
    flaskLogic.move_time = 0
    flaskLogic.original_slot = -1
    flaskLogic.finished = false
end

local function IsFlaskItem(item)
    if not item then return false end
    local name = Ability.GetName(item)
    for _, target in ipairs(FLASK_TARGET_ITEMS) do
        if name == target then return true end
    end
    return false
end

-- ФУНКЦИЯ - работает ТОЛЬКО на точке фласки
local function HandleFlask(me, p, heroPos, myPos)
    local f = flaskLogic
    
    if not f.is_active or f.finished then return end
    
    -- ГЛАВНАЯ ПРОВЕРКА: мы должны быть на точке фласки ВСЁ ВРЕМЯ
    if not myPos or (myPos - FLASK_POINT):Length2D() > 100 then 
        return 
    end

    -- ЭТАП 1: ПЕРЕМЕЩЕНИЕ ФЛАСКИ В 0 СЛОТ (ТОЛЬКО НА ТОЧКЕ)
    if not f.was_moved then
        for i = 0, 8 do
            local it = NPC.GetItemByIndex(me, i)
            if it and IsFlaskItem(it) then
                f.original_slot = i
                
                if i == 0 then
                    -- Фласка уже в 0 слоте - сразу используем
                else
                    -- Свапаем фласку в 0 слот ТОЛЬКО здесь, на точке
                    Player.PrepareUnitOrders(p, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), it, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, me)
                end
                
                f.was_moved = true
                f.move_time = os.clock()
                return
            end
        end
        f.finished = true 
        return
    end

    -- ЭТАП 2: ИСПОЛЬЗОВАНИЕ ФЛАСКИ
    if f.was_moved and not f.was_used then
        local delay = os.clock() - f.move_time
        if delay > 0.3 then
            local fl = NPC.GetItemByIndex(me, 0)
            if fl and IsFlaskItem(fl) then
                Player.PrepareUnitOrders(p, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, heroPos, fl, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, me)
                f.was_used = true
                f.move_time = os.clock()
            else
                f.was_used = true
                f.move_time = os.clock()
            end
        end
        return
    end

    -- ЭТАП 3: ВОЗВРАТ ПРЕДМЕТА НА МЕСТО
    if f.was_used and not f.finished then
        local delay = os.clock() - f.move_time
        if delay > 0.3 then
            if f.original_slot > 0 then
                local item_in_slot_0 = NPC.GetItemByIndex(me, 0)
                if item_in_slot_0 then
                    Player.PrepareUnitOrders(p, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, f.original_slot, Vector(0,0,0), item_in_slot_0, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, me)
                end
            end
            f.finished = true 
            f.is_active = false
            
        end
        return
    end
end

local SCAN_POINT   = Vector(-4248, 15252, 256)
local LEFT_PLATE   = Vector(-4613, 14782, 256)
local RIGHT_PLATE  = Vector(-3834, 14778, 256)
local POINT_1      = Vector(-4077, 14241, 256)
local POINT_2      = Vector(-3844, 13397, 256)
local POINT_3      = Vector(-4166, 13088, 384)

-- КООРДИНАТЫ СКАРАБЕЕВ
local SCARAB_LEFT  = Vector(-5161, 5225, 640)
local SCARAB_RIGHT = Vector(-3317, 5068, 640)

-- === КООРДИНАТЫ БЛОК 2 (ВЕЙПОИНТЫ И ТП) ===
local waypoints = {
    Vector(-3759, 11790, 512),   -- WP 1
    Vector(-3124, 11028, 640),   -- WP 2
    Vector(-2520, 11500, 640),   -- WP 3
    Vector(-2445, 9829, 768),    -- WP 4
    Vector(-1697, 9705, 768),    -- WP 5
    Vector(-1614, 9251, 768),    -- WP 6
    Vector(-2254, 8899, 768),    -- WP 7
    Vector(-2767, 8057, 640),    -- WP 8 (точка сдачи ключа)
    Vector(-4211, 11951, 512),   -- WP 9
    Vector(-4507, 11308, 640),   -- WP 10
    Vector(-4567, 10168, 512),   -- WP 11
    Vector(-5387, 9467, 640),    -- WP 12
    Vector(-6327, 9310, 512),    -- WP 13
    Vector(-6257, 8206, 640)     -- WP 14 (точка ТП к боссам)
}

local GATHER_POS = Vector(-5918, 3595, 384)
local OUTPOST_1_POS = Vector(-3381, 15787, 284)
local WAIT_POS = Vector(-4244, 15704, 256)    
local OUTPOST_2_POS = Vector(-6080, 3776, 412) 
local KEY_HANDIN_WP = 8
local BOSS_TP_WP = 14
local BOSS_TP_POS = OUTPOST_2_POS

-- === КОНФИГУРАЦИЯ ===
local SHARD_NAME   = "item_dark_moon_shard"
local KNIFE_NAME   = "battlemage_2"
local RUNE_ILLUSION_NAME = "item_rune_illusions"
local ILLUSION_RUNE_TYPE = 2 -- DOTA_RUNE_ILLUSION
local ENEMY_LIST = {
    ["undying"] = true,
    ["tank"] = true,
    ["npc_trap_visage"] = true,
    ["npc_dota_zone_5_unit_3"] = true,
    ["npc_dota_zone_5_unit_1"] = true,
    ["npc_dota_zone_5_unit_2"] = true,
}
local REFLECT_MOD = "modifier_boss_nyx_assassin_dispersion_cast"
local QUEST_ITEM_NAME = "item_orb"
local BOSS_NAMES = {
    ["npc_dota_boss_nyx_1"] = true,
    ["npc_dota_boss_nyx_2"] = true,
}
local WAYPOINT_ATTACK_TARGETS = {
    ["npc_dota_zone_5_unit_3"] = 1,
    ["npc_dota_zone_5_unit_1"] = 2,
    ["npc_dota_zone_5_unit_2"] = 3,
}

-- === СОСТОЯНИЕ ===
local lastActionTime = 0
local lastMoveTime = 0
local lastAttackTime = 0
local lastItemTime = 0
local waitTimer = 0
local stage = 0 
local subStage = 1
local puzzleStage = 0 
local currentWP = 1
local item_to_return = nil
local target_slot = -1
local setupDone = false
local posBeforeTP = nil
local allItemsReady = false 
local secondBlockStarted = false
local currentSecondStage = "CLEANUP"
local ultCastDone = false
local checkedSpots = { left = false, right = false }
local prevStage = -1

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

function module.CheckInventoryForOrb(hero)
    for i = 0, 8 do
        local item = NPC.GetItemByIndex(hero, i)
        if item and Ability.GetName(item) == QUEST_ITEM_NAME then return true end
    end
    return false
end

function module.FindTP(hero)
    for i = 0, 15 do
        local item = NPC.GetItemByIndex(hero, i)
        if item and Ability.GetName(item):find("tpscroll") then return item end
    end
    return nil
end

function module.OnUpdate()
    
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end
    
    local pMe = Players.GetLocal()
    local myTeam = Entity.GetTeamNum(h)
    local myPos = Entity.GetAbsOrigin(h)
    local now = os.clock()

    -- СБРОС ЛОГИКИ ФЛАСКИ ПРИ ВХОДЕ В STAGE 3
    if prevStage ~= 3 and stage == 3 then
        ResetFlaskLogic()
    end
    prevStage = stage

    if puzzleStage == 4 then secondBlockStarted = true end

    if secondBlockStarted then
        if NPC.HasModifier(h, "modifier_teleporting") then
            if currentSecondStage == "TP_TO_WAIT" then currentSecondStage = "MOVING_TO_WAIT_POS" end
            if currentSecondStage == "TP_TO_BOSS" then currentSecondStage = "BOSS_FIGHT" end
            if currentSecondStage == "TP_TO_FINAL" then 
                _G.GlobalPhase = 6
                currentSecondStage = "FINISHED" 
            end
            return 
        end

        if currentSecondStage == "CLEANUP" then
            local targetPos = waypoints[currentWP]
            if not targetPos then 
                Log.Write("[БЛОК 2] CLEANUP завершен, переход на BOSS_FIGHT")
                currentSecondStage = "BOSS_FIGHT"
                return 
            end
            
            local distToWP = (myPos - targetPos):Length2D()
            if distToWP < 200 then
                Log.Write(string.format("[CLEANUP] WP %d: расстояние %.1f м", currentWP, distToWP))
            end
            local isMovingOnly = (currentWP == KEY_HANDIN_WP or currentWP == BOSS_TP_WP)
            
            local bestTarget = nil
            local minDist = 99999
            
            if not isMovingOnly then
                local enemies = Entity.GetUnitsInRadius(h, (currentWP == 8 and 300 or 700), Enum.TeamType.TEAM_ENEMY)
                for _, enemy in ipairs(enemies) do
                    if enemy and Entity.IsAlive(enemy) then
                        local enemyName = NPC.GetUnitName(enemy)
                        if ENEMY_LIST[enemyName] then
                            local d = (myPos - Entity.GetAbsOrigin(enemy)):Length2D()
                            if d < minDist then
                                minDist = d
                                bestTarget = enemy
                            end
                        end
                    end
                end
            end

            if bestTarget then
                if now - lastAttackTime > 0.5 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastAttackTime = now
                end
            else
                if distToWP > 70 then
                    if now - lastMoveTime > 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                else
                    if currentWP == KEY_HANDIN_WP then
                        Log.Write("[CLEANUP] WP 8 достигнут: точка сдачи ключа")
                    end

                    if currentWP == BOSS_TP_WP then
                        Log.Write("[CLEANUP] WP 14 достигнут: телепортируемся к боссам")
                        currentSecondStage = "TP_TO_BOSS"
                        return
                    end

                    if currentWP < #waypoints then 
                        currentWP = currentWP + 1
                        Log.Write(string.format("[CLEANUP] Переход на WP %d", currentWP))
                        waitTimer = 0
                    else 
                        Log.Write("[CLEANUP] Все вейпоинты пройдены, переход на BOSS_FIGHT")
                        currentSecondStage = "BOSS_FIGHT" 
                    end
                end
            end

        elseif currentSecondStage == "TP_TO_BOSS" then
            local tp = module.FindTP(h)
            if tp and Ability.IsReady(tp) then
                if now - lastActionTime > 2.0 then
                    Log.Write("[TP_TO_BOSS] Кастуем ТП к боссам")
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, BOSS_TP_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastActionTime = now
                end
            end

        elseif currentSecondStage == "BOSS_FIGHT" then
            Log.Write("[BOSS_FIGHT] Этап боса активирован")
            local hasOrb = module.CheckInventoryForOrb(h)
            
            local droppedItems = PhysicalItems.GetAll()
            for _, pItem in ipairs(droppedItems) do
                local itemEntity = PhysicalItem.GetItem(pItem)
                if itemEntity and Ability.GetName(itemEntity) == QUEST_ITEM_NAME then
                    if now - lastItemTime > 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pItem, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastItemTime = now
                    end
                    return
                end
            end

            if (myPos - SCARAB_LEFT):Length2D() < 150 then checkedSpots.left = true end
            if (myPos - SCARAB_RIGHT):Length2D() < 150 then checkedSpots.right = true end

            if hasOrb and checkedSpots.left and checkedSpots.right then
                currentSecondStage = "GO_TO_GATHER"
                return
            end

            local enemies = Entity.GetUnitsInRadius(h, 3000, Enum.TeamType.TEAM_ENEMY)
            local bestBoss = nil
            local minBossDist = 99999
            local bestUnit = nil
            local bestUnitPriority = 99999
            local minUnitDist = 99999

            for _, enemy in ipairs(enemies) do
                if enemy and Entity.IsAlive(enemy) then
                    local enemyName = NPC.GetUnitName(enemy)
                    local d = (myPos - Entity.GetAbsOrigin(enemy)):Length2D()

                    if BOSS_NAMES[enemyName] then
                        if d < minBossDist then
                            minBossDist = d
                            bestBoss = enemy
                        end
                    else
                        local prio = WAYPOINT_ATTACK_TARGETS[enemyName]
                        if prio then
                            if prio < bestUnitPriority or (prio == bestUnitPriority and d < minUnitDist) then
                                bestUnitPriority = prio
                                minUnitDist = d
                                bestUnit = enemy
                            end
                        end
                    end
                end
            end

            local bestTarget = bestBoss or bestUnit

            if bestTarget then
                if NPC.HasModifier(bestTarget, REFLECT_MOD) then
                    if now - lastMoveTime > 0.3 then
                        local runPos = myPos + (myPos - Entity.GetAbsOrigin(bestTarget)):Normalized() * 500
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, runPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                else
                    local knife = NPC.GetItem(h, KNIFE_NAME, true) or NPC.GetItem(h, "item_" .. KNIFE_NAME, true)
                    if knife and Ability.IsReady(knife) and now - lastItemTime > 0.4 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), knife, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastItemTime = now
                    end
                    
                    if now - lastAttackTime > 0.5 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastAttackTime = now
                    end
                end
            else
                local nextCheck = nil
                if not checkedSpots.left then nextCheck = SCARAB_LEFT
                elseif not checkedSpots.right then nextCheck = SCARAB_RIGHT end

                if nextCheck then
                    if now - lastMoveTime > 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, nextCheck, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                end
            end

        elseif currentSecondStage == "GO_TO_GATHER" then
            local distToGather = (myPos - GATHER_POS):Length2D()
            if distToGather > 100 then
                if distToGather < 500 then
                    Log.Write(string.format("[GO_TO_GATHER] Расстояние: %.1f м", distToGather))
                end
                if now - lastMoveTime > 0.3 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, GATHER_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMoveTime = now
                end
            else
                Log.Write("[GO_TO_GATHER] Достигли точки, готово к телепортации")
                currentSecondStage = "TP_TO_WAIT"
            end

        elseif currentSecondStage == "TP_TO_WAIT" then
            Log.Write("[TP_TO_WAIT] Ищем ТП и готовимся выходить")
            local tp = module.FindTP(h)
            if tp and Ability.IsReady(tp) then
                if now - lastActionTime > 2.0 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, OUTPOST_1_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastActionTime = now
                end
            end

        elseif currentSecondStage == "MOVING_TO_WAIT_POS" then
            local distToWait = (myPos - WAIT_POS):Length2D()
            if (myPos - GATHER_POS):Length2D() > 2000 then
                if distToWait > 150 then
                    if now - lastMoveTime > 0.5 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, WAIT_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                else
                    Log.Write("[MOVING_TO_WAIT_POS] Достигли WAIT_POS, ожидаем CD")
                    currentSecondStage = "WAITING_FOR_CD"
                end
            end

        elseif currentSecondStage == "WAITING_FOR_CD" then
            Log.Write("[WAITING_FOR_CD] Ждём готовности ТП для финального завершения")
            local tp = module.FindTP(h)
            if tp and Ability.IsReady(tp) then currentSecondStage = "TP_TO_FINAL" end

        elseif currentSecondStage == "TP_TO_FINAL" then
            local tp = module.FindTP(h)
            if tp and Ability.IsReady(tp) then
                if now - lastActionTime > 2.0 then
                    Log.Write("[TP_TO_FINAL] ФИНАЛЬНАЯ ТЕЛЕПОРТАЦИЯ! Скрипт завершен!")
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, OUTPOST_2_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastActionTime = now
                    _G.GlobalPhase = 6
                end
            end
        end

    else
        -- ПЕРВЫЙ БЛОК
        
        if stage == 0 then
            local heart = NPC.GetItem(h, LICH_HEART, true)
            if heart and now - lastActionTime > 0.4 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM, nil, myPos, heart, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now
                return
            end
            for i = 6, 8 do
                local bpItem = NPC.GetItemByIndex(h, i)
                if bpItem and Ability.GetName(bpItem) ~= LICH_HEART then
                    for j = 0, 5 do
                        if not NPC.GetItemByIndex(h, j) then
                            if now - lastActionTime > 0.4 then
                                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, j, Vector(0,0,0), bpItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                                lastActionTime = now
                            end
                            return
                        end
                    end
                end
            end
        end

        if allItemsReady then
            local myIllus = {}
            local npcs = NPCs.GetAll()
            for _, n in ipairs(npcs) do
                if n and Entity.IsAlive(n) and NPC.IsIllusion(n) and Entity.GetTeamNum(n) == myTeam then
                    table.insert(myIllus, n)
                end
            end

            if #myIllus < 2 then
                local rItem = NPC.GetItem(h, RUNE_ILLUSION_NAME, true)
                if rItem and now - lastActionTime > 0.2 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), rItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastActionTime = now
                    return
                end

                local mapRunes = Runes.GetAll()
                local nearestIllusionRune = nil
                local nearestIllusionDist = 99999
                for _, r in ipairs(mapRunes) do
                    if r and Rune.GetRuneType(r) == ILLUSION_RUNE_TYPE then
                        local rPos = Entity.GetAbsOrigin(r)
                        if rPos then
                            local d = (myPos - rPos):Length2D()
                            if d < nearestIllusionDist then
                                nearestIllusionDist = d
                                nearestIllusionRune = r
                            end
                        end
                    end
                end

                if nearestIllusionRune then
                    local rPos = Entity.GetAbsOrigin(nearestIllusionRune)
                    if nearestIllusionDist > 250 then
                        if now - lastMoveTime > 0.2 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, rPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMoveTime = now
                        end
                    else
                        if now - lastActionTime > 0.2 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_RUNE, nearestIllusionRune, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastActionTime = now
                        end
                    end
                    return
                end

                local pItems = PhysicalItems.GetAll()
                local nearestDroppedRune = nil
                local nearestDroppedDist = 99999
                for _, pItem in ipairs(pItems) do
                    local it = PhysicalItem.GetItem(pItem)
                    if it and Ability.GetName(it) == RUNE_ILLUSION_NAME then
                        local pPos = Entity.GetAbsOrigin(pItem) or PhysicalItem.GetPosition(pItem)
                        if pPos then
                            local d = (myPos - pPos):Length2D()
                            if d < nearestDroppedDist then
                                nearestDroppedDist = d
                                nearestDroppedRune = pItem
                            end
                        end
                    end
                end

                if nearestDroppedRune then
                    if nearestDroppedDist > 250 then
                        local pPos = Entity.GetAbsOrigin(nearestDroppedRune) or PhysicalItem.GetPosition(nearestDroppedRune)
                        if pPos and now - lastMoveTime > 0.2 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, pPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMoveTime = now
                        end
                    else
                        if now - lastActionTime > 0.2 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, nearestDroppedRune, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastActionTime = now
                        end
                    end
                    return
                end
            end

            if puzzleStage == 0 then
                if (myPos - SCAN_POINT):Length2D() > 70 then
                    if now - lastMoveTime > 0.3 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, SCAN_POINT, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                else puzzleStage = 1 end
                return
            end

            if #myIllus >= 2 then
                if now - lastMoveTime > 0.5 then
                    local i1, i2 = myIllus[1], myIllus[2]
                    local d1 = (Entity.GetAbsOrigin(i1) - LEFT_PLATE):Length2D()
                    local d2 = (Entity.GetAbsOrigin(i2) - LEFT_PLATE):Length2D()
                    local left = (d1 < d2) and i1 or i2
                    local right = (d1 < d2) and i2 or i1
                    if (Entity.GetAbsOrigin(left) - LEFT_PLATE):Length2D() > 50 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, LEFT_PLATE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, left)
                    end
                    if (Entity.GetAbsOrigin(right) - RIGHT_PLATE):Length2D() > 50 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, RIGHT_PLATE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, right)
                    end
                    lastMoveTime = now
                end
            end

            local illReady = false
            if #myIllus >= 2 then
                local onL = (Entity.GetAbsOrigin(myIllus[1]) - LEFT_PLATE):Length2D() < 150 or (Entity.GetAbsOrigin(myIllus[2]) - LEFT_PLATE):Length2D() < 150
                local onR = (Entity.GetAbsOrigin(myIllus[1]) - RIGHT_PLATE):Length2D() < 150 or (Entity.GetAbsOrigin(myIllus[2]) - RIGHT_PLATE):Length2D() < 150
                if onL and onR then illReady = true end
            end

            if illReady then
                if puzzleStage == 1 then
                    if (myPos - POINT_1):Length2D() > 70 then
                        if now - lastMoveTime > 0.3 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_1, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMoveTime = now
                        end
                    else
                        if waitTimer == 0 then waitTimer = now end
                        if now - waitTimer >= 1.0 then puzzleStage = 2; waitTimer = 0 end
                    end
                elseif puzzleStage == 2 then
                    if (myPos - POINT_2):Length2D() > 70 then
                        if now - lastMoveTime > 0.3 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_2, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMoveTime = now
                        end
                    else puzzleStage = 3 end
                elseif puzzleStage == 3 then
                    if (myPos - POINT_3):Length2D() > 70 then
                        if now - lastMoveTime > 0.3 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_3, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMoveTime = now
                        end
                    else
                        if waitTimer == 0 then waitTimer = now end
                        if now - waitTimer >= 7.0 then puzzleStage = 4 end
                    end
                end
            end
            return 
        end

        -- ЛОГИКА ПРЕДМЕТОВ
        if (myPos - KEY_TARGET_2):Length2D() <= 200 then
            local shard = NPC.GetItem(h, SHARD_NAME, true)
            local knife = NPC.GetItem(h, KNIFE_NAME, true) or NPC.GetItem(h, "item_" .. KNIFE_NAME, true)
            if shard then
                setupDone = false 
                if now - lastActionTime > 1.0 then
                    local s_slot = -1
                    for i=0,8 do if NPC.GetItemByIndex(h, i) == shard then s_slot = i break end end
                    if s_slot <= 5 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastActionTime = now
                    else
                        local free = -1
                        for i=0,5 do if not NPC.GetItemByIndex(h,i) then free = i break end end
                        if free ~= -1 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, free, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        else
                            item_to_return = NPC.GetItemByIndex(h, 0); target_slot = 0
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 0, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        end
                        lastActionTime = now
                    end
                end
                return 
            end
            if not shard and item_to_return and target_slot ~= -1 then
                if now - lastActionTime > 0.8 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, target_slot, Vector(0,0,0), item_to_return, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    item_to_return = nil; target_slot = -1; lastActionTime = now
                end
                return
            end
            if not knife and not item_to_return then
                if not setupDone then
                    Engine.ExecuteCommand("dota_clear_quickbuy")
                    Engine.SetQuickBuy(KNIFE_NAME, true)
                    setupDone = true
                end
                if now - lastActionTime >= 0.2 then
                    Engine.ExecuteCommand("dota_purchase_quickbuy")
                    lastActionTime = now
                end
            else allItemsReady = true end
        end

        -- МАРШРУТ И КЛЮЧ
        for i = 0, 5 do
            local item = NPC.GetItemByIndex(h, i)
            if item and Ability.GetName(item) == KEY_NAME then
                for j = 6, 8 do
                    if not NPC.GetItemByIndex(h, j) then
                        if now - lastActionTime > 0.5 then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, j, Vector(0,0,0), item, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastActionTime = now
                        end
                        break
                    end
                end
            end
        end

        local hasKey = false
        for i = 0, 8 do
            local item = NPC.GetItemByIndex(h, i)
            if item and Ability.GetName(item) == KEY_NAME then hasKey = true; break end
        end

        if hasKey then
            if stage < 5 then stage = 5; subStage = 1; waitTimer = 0 end
            local target = (subStage == 1) and KEY_TARGET_1 or KEY_TARGET_2
            if (myPos - target):Length2D() > 80 then
                if now - lastMoveTime > 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, target, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMoveTime = now
                end
            else
                if subStage == 1 then
                    if waitTimer == 0 then waitTimer = now end
                    if now - waitTimer >= 1.0 then subStage = 2; waitTimer = 0 end
                end
            end
            return 
        end

        if stage == 0 then
            if (myPos - START_PLATE):Length2D() > 60 then
                if now - lastMoveTime > 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, START_PLATE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMoveTime = now
                end
            else posBeforeTP = Vector(myPos.x, myPos.y, myPos.z); stage = 1 end
        elseif stage == 1 then
            if posBeforeTP and (myPos - posBeforeTP):Length2D() > 500 then
                if (myPos - FINISH_ZONE):Length2D() > 150 then
                    if now - lastMoveTime > 0.1 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, FINAL_TARGET, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                else stage = 2 end
            end
        elseif stage == 2 then
            if (myPos - STAGE2_ENTRANCE):Length2D() > 150 then
                if (myPos - LAST_TRIGGER):Length2D() > 50 then
                    if now - lastMoveTime > 0.35 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, LAST_TRIGGER, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                end
            else stage = 3; subStage = 1 end
        
        -- STAGE 3 - ФЛАСКА
        elseif stage == 3 then
            local target = FLASK_POINT
            local distToFlask = (myPos - target):Length2D()
            
            -- ЕСЛИ УШЛИ С ТОЧКИ - сбрасываем всю логику фласки
            if flaskLogic.is_active and distToFlask > 100 then
                ResetFlaskLogic()
            end
            
            -- Активируем логику фласки только когда пришли на точку
            if distToFlask < 100 then
                if not flaskLogic.is_active and not flaskLogic.finished then
                    if waitTimer == 0 then waitTimer = now end
                    if now - waitTimer >= 0.5 then
                        flaskLogic.is_active = true
                        waitTimer = 0
                    end
                end
            end
            
            -- Запускаем HandleFlask только если мы НА ТОЧКЕ
            if flaskLogic.is_active and distToFlask < 100 then
                HandleFlask(h, pMe, myPos, myPos)
                
                if flaskLogic.finished then
                    stage = 4
                    flaskLogic.is_active = false
                end
                return
            end
            
            -- Идём к точке фласки
            if distToFlask > 60 then
                if now - lastMoveTime > 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, target, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMoveTime = now
                end
            end
            
        elseif stage == 4 then
            if (myPos - BOSS_ZONE):Length2D() > 60 then
                if now - lastMoveTime > 0.35 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, BOSS_ZONE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMoveTime = now
                end
            end
            local pItems = PhysicalItems.GetAll()
            for _, pItem in ipairs(pItems) do
                local item = PhysicalItem.GetItem(pItem)
                if item and Ability.GetName(item) == KEY_NAME then
                    if now - lastMoveTime > 0.2 then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pItem, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMoveTime = now
                    end
                    return
                end
            end
            local enemies = Entity.GetUnitsInRadius(h, 600, Enum.TeamType.TEAM_ENEMY)
            if enemies[1] and now - lastMoveTime > 0.5 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, enemies[1], Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMoveTime = now
            end
        end
    end
end

return module
