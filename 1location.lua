local script = {}

local _hudFont = Render.LoadFont("Arial", 18, Enum.FontCreate.FONTFLAG_ANTIALIAS)
local _hudColor = Color(0, 255, 128, 255)

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
local BOSS_WP_INDEX = 24
local MINION_WP_INDEX = 25
local SHOP_WP_INDEX = 23
local DARK_MOON_SHARD = "item_dark_moon_shard"
local MOON_SHARD_SOLO = "item_dark_moon_shard"
local MOON_SHARD_TEAM = "item_moon_shard"

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

local function GetShardName()
    return HasTeammate() and MOON_SHARD_TEAM or MOON_SHARD_SOLO
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
    Vector(-14037, -14737, 512),  -- 23 (Магазин)
    Vector(-12432, -11892, 512),  -- 24 (Босс)
    Vector(-11541, -11240, 512)   -- 25 (Подсосы)
}

local function EstimateMedusaWaypoint(medusaPos)
    if not medusaPos then return #WAYPOINTS + 1 end
    local bestIdx = 1
    local bestDist = 999999
    for i = 1, #WAYPOINTS do
        local d = (medusaPos - WAYPOINTS[i]):Length2D()
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
    end
    if bestDist < 250 then return bestIdx + 1 end
    return bestIdx
end

local QUELLING_SHOP_POS = Vector(-14037, -14737, 512)

local currentWP = 1
local killedQuestCount = 0
local lastQuestTarget = nil
local lastMoveTime = 0
local lastPickTime = 0
local lockedTarget = nil
local lockedTargetName = nil
local bossKilled = false
local flaskMovedToBackpack = false
local lastFlaskMoveTry = 0
local shardBought = false
local shardQuickBuyReady = false
local lastShardBuyTime = 0
local quellingBuyDone = false
local quellingQuickBuyReady = false
local lastQuellingBuyTime = 0

local function IsValidEnemy(myHero, npc)
    return npc and Entity.IsAlive(npc) and not Entity.IsDormant(npc) and not Entity.IsSameTeam(myHero, npc)
end

local function CanChaseTarget(myPos, npc)
    if not npc then return false end
    local npcPos = Entity.GetAbsOrigin(npc)
    if not npcPos then return false end
    return (npcPos - myPos):Length2D() <= CHASE_RADIUS
end

local function FindItemByName(hero, itemName)
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(hero, i)
        if it and Ability.GetName(it) == itemName then
            return it, i
        end
    end
    return nil, -1
end

local function SetQuickBuyCompat(itemName)
    if not itemName or not Engine then return end
    local qbName = itemName
    if itemName:sub(1, 5) == "item_" then
        qbName = itemName:sub(6)
    end
    if type(Engine.SetQuickBuy) == "function" then Engine.SetQuickBuy(qbName, true) end
    if type(Engine.SetQuikbuy) == "function" then Engine.SetQuikbuy(qbName, true) end
    if type(Engine.SetQuikBuy) == "function" then Engine.SetQuikBuy(qbName, true) end
    Engine.ExecuteCommand("dota_quickbuy " .. qbName)
end

function script.OnUpdate()
    if _G.GlobalPhase ~= 1 then return end

    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end

    local myPlayer = Players.GetLocal()
    if not myPlayer then return end

    local myPos = Entity.GetAbsOrigin(myHero)
    local now = os.clock()

    _G.HeroMove = "[1loc] Patrol WP" .. currentWP .. "/" .. #WAYPOINTS
    _G.HeroAction = "[1loc] Searching enemies"

    -- Каждый тик: если flask в активных слотах (0-5) — перекинуть в ранец
    for i = 0, 5 do
        local item = NPC.GetItemByIndex(myHero, i)
        if item then
            local itemName = Ability.GetName(item)
            if itemName then
                local lower = itemName:lower()
                if lower:find("flask") or lower:find("bkb") or lower:find("immune") then
                    local targetSlot = 6
                    for bp = 6, 8 do
                        if not NPC.GetItemByIndex(myHero, bp) then
                            targetSlot = bp
                            break
                        end
                    end
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, targetSlot, Vector(0,0,0), item, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    return
                end
            end
        end
    end

    if currentWP > #WAYPOINTS then
        _G.HeroMove = "[1loc] Standing"
        _G.HeroAction = "[1loc] DONE -> Phase 2"
        _G.GlobalPhase = 2
        return
    end

    -- 0. НЕ-МЕДУЗА: покупаем quelling_blade в магазине в самом начале
    if not IsMedusa(myHero) and not quellingBuyDone then
        local axe, _ = FindItemByName(myHero, ITEM_TO_PICK)
        if axe then
            quellingBuyDone = true
        else
            local distToShop = (myPos - QUELLING_SHOP_POS):Length2D()
            if distToShop > 150 then
                _G.HeroMove = "[1loc] Moving to shop (" .. math.floor(distToShop) .. ")"
                _G.HeroAction = "[1loc] Go buy quelling"
                if now - lastMoveTime > 0.3 then
                    Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, QUELLING_SHOP_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                    lastMoveTime = now
                end
            else
                _G.HeroMove = "[1loc] At shop"
                _G.HeroAction = "[1loc] Buying quelling"
                if now - lastQuellingBuyTime >= 0.3 then
                    if not quellingQuickBuyReady then
                        Engine.ExecuteCommand("dota_clear_quickbuy")
                        SetQuickBuyCompat(ITEM_TO_PICK)
                        quellingQuickBuyReady = true
                    end
                    Engine.ExecuteCommand("dota_purchase_quickbuy")
                    lastQuellingBuyTime = now
                end
            end
            return
        end
    end

    -- 0.1 ПОИСК ПРЕДМЕТА НА ЗЕМЛЕ (Приоритет выше атаки)
    if not (IsMedusa(myHero) and HasTeammate()) then
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
                        _G.HeroMove = "[1loc] Moving to item (" .. math.floor(distToItem) .. ")"
                        _G.HeroAction = "[1loc] Pick quelling"
                        if now - lastPickTime > 0.5 then
                            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, pItem, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
                            lastPickTime = now
                        end
                        return
                    end
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

    local searchRadius = bossLock and CHASE_RADIUS or AGGRO_RADIUS
    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if npc and Entity.IsAlive(npc) and not Entity.IsSameTeam(myHero, npc) and not Entity.IsDormant(npc) then
            local npcPos = Entity.GetAbsOrigin(npc)
            local distToHero = (npcPos - myPos):Length2D()
            
            if distToHero <= searchRadius then
                local name = NPC.GetUnitName(npc)
                if name == QUEST_UNIT then
                    questTarget = npc
                elseif name == BOSS_NAME and not bossKilled then
                    bossTarget = npc
                elseif OTHER_UNITS[name] then
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
        elseif questTarget then
            activeTarget = questTarget
        elseif normalTarget then
            activeTarget = normalTarget
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
        local shortName = lockedTargetName:gsub("npc_dota_", "")
        _G.HeroMove = "[1loc] In combat"
        _G.HeroAction = "[1loc] ATK: " .. shortName
        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, activeTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
        return
    end

    -- 3. СЧЕТЧИК КВЕСТОВЫХ
    if lastQuestTarget and not Entity.IsAlive(lastQuestTarget) then
        killedQuestCount = killedQuestCount + 1
        lastQuestTarget = nil
        print("Квестовых убито: " .. killedQuestCount .. "/11")
    end

    -- 3.5. ПОДБОР МЕШОЧКОВ ЗОЛОТА (наступаем на них)
    local physicalItems = PhysicalItems.GetAll()
    local bestGold = nil
    local bestGoldDist = 500
    for i = 1, #physicalItems do
        local pItem = physicalItems[i]
        if pItem and not Entity.IsDormant(pItem) then
            local itemEntity = PhysicalItem.GetItem(pItem)
            if itemEntity then
                local itemName = Ability.GetName(itemEntity)
                if itemName and itemName:find("bag_of_gold") then
                    local itemPos = Entity.GetAbsOrigin(pItem)
                    if itemPos then
                        local d = (itemPos - myPos):Length2D()
                        if d < bestGoldDist then
                            bestGoldDist = d
                            bestGold = itemPos
                        end
                    end
                end
            end
        end
    end

    if bestGold and now - lastMoveTime > 0.3 then
        _G.HeroMove = "[1loc] Moving to gold (" .. math.floor(bestGoldDist) .. ")"
        _G.HeroAction = "[1loc] Pick gold bag"
        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, bestGold, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
        lastMoveTime = now
        return
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

        -- Покупка dark_moon_shard на шоп-вейпоинте
        if currentWP == SHOP_WP_INDEX and not shardBought then
            _G.HeroMove = "[1loc] At shop WP"
            _G.HeroAction = "[1loc] Buy shard"
            local shardName = GetShardName()
            local shard, _ = FindItemByName(myHero, shardName)
            if shard then
                shardBought = true
            else
                if now - lastShardBuyTime >= 0.2 then
                    if not shardQuickBuyReady then
                        Engine.ExecuteCommand("dota_clear_quickbuy")
                        SetQuickBuyCompat(shardName)
                        shardQuickBuyReady = true
                    end
                    Engine.ExecuteCommand("dota_purchase_quickbuy")
                    lastShardBuyTime = now
                end
                return
            end
        end

        currentWP = currentWP + 1
        -- Non-Medusa с тиммейтом: не может обогнать Медузу по вейпоинтам
        if HasTeammate() and not IsMedusa(myHero) then
            local medusa = FindTeammateMedusa()
            if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                local medusaPos = Entity.GetAbsOrigin(medusa)
                local medusaWP = EstimateMedusaWaypoint(medusaPos)
                if currentWP > medusaWP then
                    currentWP = currentWP - 1
                    _G.HeroMove = "[1loc] Waiting for Medusa"
                    _G.HeroAction = "[1loc] Can't overtake (WP" .. currentWP .. " vs M:" .. medusaWP .. ")"
                    return
                end
            end
        end
        print("Вейпоинт достигнут: " .. (currentWP - 1) .. " -> Идем к " .. currentWP)
    end
end

function script.OnDraw()
    if _G.GlobalPhase ~= 1 then return end
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