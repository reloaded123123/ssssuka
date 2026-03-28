local script = {}

local _hudFont = Render.LoadFont("Arial", 18, Enum.FontCreate.FONTFLAG_ANTIALIAS)
local _hudColor = Color(0, 255, 128, 255)

-- НОВЫЕ ДАННЫЕ ИЗ ТВОЕГО ЗАПРОСА
local TARGET_ITEM_NAME = "item_gem_shard" 
local QUICKBUY_NAME = "gem_shard"          
local SHOP_POS = Vector(-12952, -2939, 640)
local MOON_SHARD_NAME = ""
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
    "item_lich_heart",
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
local AFTER_CUT_POS = Vector(-13480, 3622, 768)

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
local cutterSwapActive = false
local cutterSwapSourceSlot = -1
local cutterSwapTargetSlot = -1
local cutterSwapLastAction = 0
local plateCutterReady = false
local plateNeedRestore = false
local afterCutStep = 0
local afterCutTimer = 0

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

local function TeammateHasItem(itemName)
    local mate = FindTeammateHero()
    if not mate then return false end
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(mate, i)
        if it and Ability.GetName(it) == itemName then return true end
    end
    return false
end

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

local function FindCutterItem(hero)
    if not hero then return nil, -1 end
    for i = 0, 8 do
        local it = NPC.GetItemByIndex(hero, i)
        if it then
            local name = Ability.GetName(it):lower()
            if name:find("quelling") or name:find("bfury") or name:find("battlefury") then
                return it, i
            end
        end
    end
    return nil, -1
end

local function EnsureCutterInActiveSlot(hero, player, now)
    if cutterSwapActive then
        local inActive = NPC.GetItemByIndex(hero, cutterSwapTargetSlot)
        if inActive then
            local n = Ability.GetName(inActive):lower()
            if n:find("quelling") or n:find("bfury") or n:find("battlefury") then
                return inActive, true
            end
        end
    end

    local cutter, slot = FindCutterItem(hero)
    if not cutter then return nil, false end

    if slot <= 5 then
        return cutter, true
    end

    if now - cutterSwapLastAction < 0.35 then
        return nil, false
    end

    local targetSlot = -1
    for i = 0, 5 do
        if not NPC.GetItemByIndex(hero, i) then
            targetSlot = i
            break
        end
    end
    if targetSlot == -1 then
        targetSlot = 0
    end

    Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, targetSlot, Vector(0,0,0), cutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
    cutterSwapActive = true
    cutterSwapSourceSlot = slot
    cutterSwapTargetSlot = targetSlot
    cutterSwapLastAction = now
    return nil, false
end

local function RestoreCutterAfterCut(hero, player, now)
    if not cutterSwapActive then return false end
    if now - cutterSwapLastAction < 0.35 then return true end

    local displaced = NPC.GetItemByIndex(hero, cutterSwapSourceSlot)
    if displaced then
        Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, cutterSwapTargetSlot, Vector(0,0,0), displaced, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
    else
        local cutterNow = NPC.GetItemByIndex(hero, cutterSwapTargetSlot)
        if cutterNow then
            Player.PrepareUnitOrders(player, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, cutterSwapSourceSlot, Vector(0,0,0), cutterNow, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero)
        end
    end

    cutterSwapLastAction = now
    cutterSwapActive = false
    cutterSwapSourceSlot = -1
    cutterSwapTargetSlot = -1
    return true
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
    if _G.GlobalPhase ~= 6 then return end

   
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
            local distToShop = (myPos - SHOP_POS):Length2D()
            _G.HeroMove = "[4loc] Moving to shop (" .. math.floor(distToShop) .. ")"
            _G.HeroAction = "[4loc] Buy step " .. buyStep
            if distToShop > 150 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, SHOP_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else 
                _G.HeroMove = "[4loc] At shop"
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
        local tName = NPC.GetUnitName(bestTarget):gsub("npc_dota_", "")
        _G.HeroMove = "[4loc] In combat"
        _G.HeroAction = "[4loc] ATK: " .. tName
        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, bestTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h, false, true)
        return
    end

    -- ПОСЛЕ ЗАВЕРШЕНИЯ ВЕЙПОИНТОВ ИЛИ ПРИ ОСОБЫХ ШАГАХ
    if currentWaypoint > #WAYPOINTS or huntBoss or pickingHeart or onPlateStep then
        
        -- Non-Medusa с тиммейтом: овцы/плиты/рубка - только Медуза
        -- Но если босс виден или убит (сердце) — non-Medusa тоже участвует
        if HasTeammate() and not IsMedusa(h) and not huntBoss and not pickingHeart then
            -- Проверяем: босс рядом? Тогда non-Medusa тоже идёт в бой
            if bossVisible then
                huntBoss = true
            else
                -- Проверяем: может сердце уже на земле? Тогда подбираем
                local heartOnGround = false
                local mapItemsCheck = PhysicalItems.GetAll()
                for _, item in ipairs(mapItemsCheck) do
                    local d = PhysicalItem.GetItem(item)
                    if d and Ability.GetName(d) == LICH_HEART then
                        heartOnGround = true
                        break
                    end
                end
                if heartOnGround then
                    pickingHeart = true
                else
                    -- Non-Medusa просто следует за Медузой, не делая специальных действий
                    local medusa = FindTeammateMedusa()
                    if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                        local medusaPos = Entity.GetAbsOrigin(medusa)
                        local distToMedusa = (myPos - medusaPos):Length2D()
                        _G.HeroMove = "[4loc] Following Medusa (" .. math.floor(distToMedusa) .. ")"
                        _G.HeroAction = "[4loc] Medusa does special actions"
                        if distToMedusa > 400 then
                            if now - lastMove >= moveDelay then
                                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, medusaPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                                lastMove = now
                            end
                        end
                        return
                    end
                end
            end
        end
        
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
                _G.GlobalPhase = 7
                return
            end
            return
        end

        if pickingHeart then
            -- Медуза с тиммейтом: не подбирает предметы, ждёт пока тиммейт возьмёт
            if IsMedusa(h) and HasTeammate() then
                _G.HeroMove = "[4loc] Waiting at boss"
                _G.HeroAction = "[4loc] Wait teammate heart"
                if TeammateHasItem(LICH_HEART) then
                    _G.GlobalPhase = 7
                    return
                end
                -- Ждём у босса
                if (myPos - BOSS_POS):Length2D() > 300 then
                    if now - lastMove >= moveDelay then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, BOSS_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMove = now
                    end
                end
                return
            end
            _G.HeroMove = "[4loc] Searching heart drop"
            _G.HeroAction = "[4loc] Pick lich heart"
            local mapItems = PhysicalItems.GetAll()
            for _, item in ipairs(mapItems) do
                local d = PhysicalItem.GetItem(item)
                if d and Ability.GetName(d) == LICH_HEART then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM, item, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    return
                end
            end
            -- Heart не видно — идём к позиции босса, чтобы приблизиться к дропу
            if (myPos - BOSS_POS):Length2D() > 200 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, BOSS_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            end
            return
        end

        -- ПЛИТА
        if onPlateStep then
            _G.HeroMove = "[4loc] Moving to plate"
            _G.HeroAction = "[4loc] Cut trees -> plate"
            local distToPlate = (myPos - PLATE_POS):Length2D()
            if distToPlate > 50 then
                if now - lastMove >= 0.15 then 
                    -- Достаем топор только когда почти подошли к плите.
                    if distToPlate <= 320 and not plateCutterReady then
                        local cutter, cutterReady = EnsureCutterInActiveSlot(h, pMe, now)
                        if not cutterReady then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, PLATE_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastMove = now
                            return
                        end
                        plateCutterReady = true
                        if cutterSwapActive then
                            plateNeedRestore = true
                        end
                    end

                    local cutter = nil
                    if plateCutterReady then
                        local c, cSlot = FindCutterItem(h)
                        if c and cSlot <= 5 then
                            cutter = c
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
                -- После завершения шага возвращаем инвентарь один раз.
                if plateNeedRestore and cutterSwapActive then
                    if RestoreCutterAfterCut(h, pMe, now) then
                        plateNeedRestore = false
                        plateCutterReady = false
                        return
                    end
                end
                plateNeedRestore = false
                plateCutterReady = false
                onPlateStep = false
                afterCutStep = 1
                afterCutTimer = 0
            end
            return
        end

        -- ТОЧКА ПОСЛЕ РУБКИ
        if afterCutStep == 1 then
            local distToAfterCut = (myPos - AFTER_CUT_POS):Length2D()
            if distToAfterCut > 100 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, AFTER_CUT_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                if afterCutTimer == 0 then
                    afterCutTimer = now
                end
                if now - afterCutTimer >= 1.0 then
                    afterCutStep = 0
                    afterCutTimer = 0
                end
            end
            return
        end

        -- ОХОТА НА БОССА
        if huntBoss then
            _G.HeroMove = "[4loc] Moving to boss pos"
            _G.HeroAction = "[4loc] Hunt boss lich"
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
            _G.HeroMove = "[4loc] Moving to sheep #" .. releaseIndex .. " (" .. math.floor(dist) .. ")"
            _G.HeroAction = "[4loc] Sheep #" .. releaseIndex
            
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
                    plateCutterReady = false
                    plateNeedRestore = false
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
        local distToWp = (myPos - wp):Length2D()
        _G.HeroMove = "[4loc] Patrol WP" .. currentWaypoint .. "/" .. #WAYPOINTS .. " (" .. math.floor(distToWp) .. ")"
        _G.HeroAction = "[4loc] Searching enemies"

        -- Non-Medusa в команде: следует позади Медузы (75 юнитов назад)
        if HasTeammate() and not IsMedusa(h) then
            local medusa = FindTeammateMedusa()
            if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                local medusaPos = Entity.GetAbsOrigin(medusa)
                local dir = (wp - medusaPos):Normalized()
                local behindPos = medusaPos - dir * 75
                local distToBehind = (myPos - behindPos):Length2D()
                _G.HeroMove = "[4loc] Behind Medusa (" .. math.floor(distToBehind) .. ")"
                _G.HeroAction = "[4loc] Following"
                if distToBehind > 50 and now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, behindPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
                local medusaWP = EstimateMedusaWaypoint(medusaPos)
                if medusaWP > 0 then currentWaypoint = math.max(1, medusaWP) end
                return
            end
        end

        if distToWp > 200 then
            if now - lastMove >= moveDelay then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, wp, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
        else
            currentWaypoint = currentWaypoint + 1
        end
    end
end

function script.OnDraw()
    if _G.GlobalPhase ~= 6 then return end
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