local script = {}

-- Точки маршрута 1
local OUTPOST_1_POS = Vector(-6016, -15680, 251)
local POINT_1 = Vector(-12269, -10841, 256)
local POINT_2_WOODS = Vector(-12368, -9945, 256)
local POINT_3_PAUSE = Vector(-13302, -9442, 256)
local POINT_4_AFTER_PAUSE = Vector(-12297, -10655, 256)
local POINT_BEFORE_BOSS_1 = Vector(-14517, -14785, 256)
local POINT_BOSS_1_LAIR = Vector(-14369, -14910, 256)
local BOSS_1_NAME = "npc_hidden_earth_boss"

-- Точка обязательной остановки после 1 босса
local WAIT_TP_POS = Vector(-12852, -14683, 256)

-- Точки маршрута 2
local OUTPOST_2_POS = Vector(-15713, -2259, 510)
local POINT_5 = Vector(-11229, 4000, 640)
local POINT_6_WOODS = Vector(-10414, 4217, 640)
-- ОБНОВЛЕННАЯ ТОЧКА БОССА 2
local POINT_BOSS_2 = Vector(-8500, 5002, 512) 
local BOSS_2_NAME = "npc_hidden_snow_boss"

-- СОСТОЯНИЕ СКРИПТА
local lastActionTime = 0
local pauseStartTime = 0
local state = "TP_TO_OUTPOST_1"
local phaseAnnounced = false
local boss2Seen = false 

local function GetCutter(h)
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(h, i)
        if it then
            local name = Ability.GetName(it):lower()
            if name:find("quelling") or name:find("bfury") then return it end
        end
    end
    return nil
end

local function GetKnives(h)
    for i = 0, 5 do
        local it = NPC.GetItemByIndex(h, i)
        if it and Ability.GetName(it):lower():find("battlemage") then return it end
    end
    return nil
end

local function HandleWoodCutting(h, pMe, myPos, targetPos)
    local cutter = GetCutter(h)
    if not cutter or not Ability.IsReady(cutter) then return false end
    local trees = Trees.InRadius(myPos, 380, true)
    local bestTree, minTreeDist = nil, 999
    local dirToTarget = (targetPos - myPos):Normalized()
    for _, tree in ipairs(trees) do
        local treePos = Entity.GetAbsOrigin(tree)
        local dot = (treePos - myPos):Normalized():Dot(dirToTarget)
        if dot > -0.5 then 
            local d = (myPos - treePos):Length2D()
            if d < minTreeDist then minTreeDist = d; bestTree = tree end
        end
    end
    if bestTree then
        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, bestTree, Vector(0,0,0), cutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
        return true
    end
    return false
end

function script.OnUpdate()
    if _G.GlobalPhase ~= 1 then return end

    if not phaseAnnounced then
        print("[PHASE 8] STARTED")
        phaseAnnounced = true
    end

    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end
    local pMe = Players.GetLocal()
    if not pMe then return end

    local now = os.clock()
    local myPos = Entity.GetAbsOrigin(h)

    -- 1. ТП НА ПЕРВЫЙ АВАНПОСТ
    if state == "TP_TO_OUTPOST_1" then
        local tp = nil
        for i = 0, 15 do
            local it = NPC.GetItemByIndex(h, i)
            if it and Ability.GetName(it) == "item_tpscroll" then tp = it break end
        end
        if tp and Ability.IsReady(tp) then
            if now - lastActionTime > 2.0 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, OUTPOST_1_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now
            end
        elseif (myPos - OUTPOST_1_POS):Length2D() < 600 then 
            state = "MOVE_TO_P1" 
        end

    -- МАРШРУТ 1
    elseif state == "MOVE_TO_P1" then
        if (myPos - POINT_1):Length2D() < 150 then state = "MOVE_TO_P2_WOODS"
        elseif now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_1, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
    
    elseif state == "MOVE_TO_P2_WOODS" then
        if (myPos - POINT_2_WOODS):Length2D() < 150 then state = "MOVE_TO_P3_PAUSE"
        else
            if now - lastActionTime >= 0.15 and HandleWoodCutting(h, pMe, myPos, POINT_2_WOODS) then lastActionTime = now; return end
            if now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_2_WOODS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
        end

    elseif state == "MOVE_TO_P3_PAUSE" then
        if (myPos - POINT_3_PAUSE):Length2D() < 150 then
            if pauseStartTime == 0 then pauseStartTime = now end
            if now - pauseStartTime >= 1.0 then state = "MOVE_TO_P4" end
        elseif now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_3_PAUSE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
    
    elseif state == "MOVE_TO_P4" then
        if (myPos - POINT_4_AFTER_PAUSE):Length2D() < 150 then state = "MOVE_TO_BEFORE_BOSS_1"
        elseif now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_4_AFTER_PAUSE, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
    
    elseif state == "MOVE_TO_BEFORE_BOSS_1" then
        if (myPos - POINT_BEFORE_BOSS_1):Length2D() < 150 then state = "FIGHT_BOSS_1"
        elseif now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_BEFORE_BOSS_1, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end

    -- БИТВА С 1 БОССОМ
    elseif state == "FIGHT_BOSS_1" then
        local boss = nil
        for _, u in ipairs(NPCs.GetAll()) do if Entity.GetUnitName(u) == BOSS_1_NAME and Entity.IsAlive(u) then boss = u; break end end
        if boss then
            local kn = GetKnives(h)
            if kn and Ability.IsReady(kn) then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), kn, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h) end
            if now - lastActionTime >= 0.5 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, boss, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
        else state = "MOVE_TO_WAIT_POS" end

    -- ТОЧКА ПОСЛЕ БОССА
    elseif state == "MOVE_TO_WAIT_POS" then
        if (myPos - WAIT_TP_POS):Length2D() < 150 then state = "TP_TO_OUTPOST_2"
        elseif now - lastActionTime >= 0.4 then
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, WAIT_TP_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastActionTime = now
        end

    -- ТП НА ВТОРОЙ АВАНПОСТ
    elseif state == "TP_TO_OUTPOST_2" then
        local tp = nil
        for i = 0, 15 do
            local it = NPC.GetItemByIndex(h, i)
            if it and Ability.GetName(it) == "item_tpscroll" then tp = it break end
        end
        if tp and Ability.IsReady(tp) then
            if now - lastActionTime > 2.0 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION, nil, OUTPOST_2_POS, tp, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now
            end
        elseif (myPos - OUTPOST_2_POS):Length2D() < 600 then state = "MOVE_TO_P5" end

    -- МАРШРУТ 2
    elseif state == "MOVE_TO_P5" then
        if (myPos - POINT_5):Length2D() < 150 then state = "MOVE_TO_P6_WOODS"
        elseif now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_5, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
    
    elseif state == "MOVE_TO_P6_WOODS" then
        if (myPos - POINT_6_WOODS):Length2D() < 150 then 
            state = "MOVE_TO_BOSS_2" -- ПРАВИЛЬНЫЙ ПЕРЕХОД
        else
            if now - lastActionTime >= 0.15 and HandleWoodCutting(h, pMe, myPos, POINT_6_WOODS) then lastActionTime = now; return end
            if now - lastActionTime >= 0.4 then Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_6_WOODS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h); lastActionTime = now end
        end

    -- НОВОЕ СОСТОЯНИЕ: ИДЕМ ПРЯМО К ТОЧКЕ БОССА
    elseif state == "MOVE_TO_BOSS_2" then
        if (myPos - POINT_BOSS_2):Length2D() < 100 then 
            state = "FIGHT_BOSS_2"
        elseif now - lastActionTime >= 0.4 then 
            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_BOSS_2, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
            lastActionTime = now 
        end

    -- БИТВА СО ВТОРЫМ БОССОМ
    elseif state == "FIGHT_BOSS_2" then
        local boss = nil
        for _, u in ipairs(NPCs.GetAll()) do 
            if Entity.GetUnitName(u) == BOSS_2_NAME and Entity.IsAlive(u) then boss = u; break end 
        end

        if boss then
            boss2Seen = true
            local kn = GetKnives(h)
            if kn and Ability.IsReady(kn) then 
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), kn, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h) 
            end
            if now - lastActionTime >= 0.5 then 
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, boss, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now 
            end
        elseif boss2Seen then
            print("[PHASE 8] BOSS 2 KILLED. FINISHING...")
            _G.GlobalPhase = "FINISHED"
            return
        else
            -- Если пришли на точку, а босса еще нет - просто ждем на месте (можно добавить легкий патруль, если надо)
            if now - lastActionTime >= 1.0 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, POINT_BOSS_2, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now
            end
        end
    end
end

return script