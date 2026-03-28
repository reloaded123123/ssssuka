local script = {}

local _hudFont = Render.LoadFont("Arial", 18, Enum.FontCreate.FONTFLAG_ANTIALIAS)
local _hudColor = Color(0, 255, 128, 255)

local UPGRADE_SHOP_POS = Vector(-5308, -10719, 832)
local BOSS_SOUL = "item_boss_soul"
local DL3_NAME_SOLO = "dragon_lance_lua3"
local DL3_NAME_TEAM = "dragon_lance_lua3"
local SHARD_NAME_SOLO = "item_dark_moon_shard"
local SHARD_NAME_TEAM = "item_dark_moon_shard"
local BOSS_NAME = "npc_dota_boss_bristleback"
local KNIFE_NAME = "battlemage"

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

local UNIT_NAMES = {
    ["npc_dota_zone_7_unit_1"] = true,
    ["npc_dota_zone_7_unit_2"] = true,
    ["npc_dota_zone_7_unit_3"] = true,
    ["npc_dota_zone_7_unit_4"] = true,
    ["npc_dust_quest"] = true,
    ["npc_dota_hero_medusa"] = true,
}

local WAYPOINTS = {
    Vector(-3783, -10469, 873),
    Vector(-2065, -10148, 749),
    Vector(-1881, -9710, 936),
    Vector(-1825, -10856, 1005),
    Vector(-462, -10562, 826),
    Vector(-2384, -11362, 538),
    Vector(-1834, -12332, 748),
    Vector(-1647, -13371, 821),
    Vector(-1346, -14407, 837),
    Vector(-1499, -15242, 875),
    Vector(-2119, -15055, 1052),
    Vector(-582, -14383, 701),
    Vector(-667, -13859, 717),
    Vector(-288, -13344, 723),
    Vector(32, -13472, 752),
    Vector(74, -14845, 845),
    Vector(230, -14522, 846),
    Vector(850, -15491, 844),
    Vector(2080, -14944, 990),
    Vector(1608, -14144, 554),
    Vector(1386, -13764, 972),
    Vector(1104, -12390, 835),
    Vector(1178, -11225, 816)
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

local upgradeStep = 0
local lastActionTime = 0
local lastMove = 0
local moveDelay = 0.3
local quickBuySet = false
local currentWpIndex = 1
local bossSpawned = false
local shopArrivalTime = 0

-- Goo puddle dodge
local activePuddles = {}
local GOO_DODGE_BUFFER = 80
local GOO_MAX_LIFETIME = 12
local dodgeStuckStart = 0
local dodgeRotation = 0
local lastDodgePos = nil

local function FindSafeEscapePos(myPos, puddles, bossEntity, puddlePos, puddleRadius, rotOffset)
    rotOffset = rotOffset or 0
    local bossPos = bossEntity and Entity.GetAbsOrigin(bossEntity) or nil
    local escapeDist = puddleRadius + GOO_DODGE_BUFFER

    local bestPos = nil
    local bestScore = -999999

    for i = 0, 11 do
        local angle = ((i + rotOffset) % 12) * math.pi / 6
        local dir = Vector(math.cos(angle), math.sin(angle), 0)
        local candidatePos = puddlePos + dir * escapeDist

        local inAnyPuddle = false
        for _, p in pairs(puddles) do
            if p.pos and (candidatePos - p.pos):Length2D() < p.radius then
                inAnyPuddle = true
                break
            end
        end

        if not inAnyPuddle then
            local score = 0
            if bossPos then
                score = score - (candidatePos - bossPos):Length2D()
            end
            -- When stuck (rotOffset > 0), ignore boss proximity, just find walkable direction
            if rotOffset == 0 then
                score = score - (candidatePos - myPos):Length2D() * 0.5
            end
            if score > bestScore then
                bestScore = score
                bestPos = candidatePos
            end
        end
    end

    if not bestPos then
        local fallbackDir = (myPos - puddlePos)
        if fallbackDir:Length2D() < 10 then fallbackDir = Vector(1, 0, 0) end
        bestPos = puddlePos + fallbackDir:Normalized() * escapeDist
    end

    return bestPos
end

local function GetKnives(h)
    if not h then 
        return nil 
    end
    for i = 0, 5 do
        local it = NPC.GetItemByIndex(h, i)
        if it then
            local itemName = Ability.GetName(it)
            if itemName:lower():find(KNIFE_NAME) then 
                return it 
            end
        end
    end
    return nil
end

function script.OnUpdate()
    if _G.GlobalPhase ~= 10 then 
        return 
    end
    
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then 
        return 
    end
    
    local pMe = Players.GetLocal()
    local myPos = Entity.GetAbsOrigin(h)
    local now = os.clock()

    if upgradeStep < 5 then
        if upgradeStep > 0 and shopArrivalTime == 0 then
            shopArrivalTime = now
        end
        if shopArrivalTime > 0 and (now - shopArrivalTime) > 20 then
            upgradeStep = 5
        end
        if upgradeStep == 0 then
            local distToShop = (myPos - UPGRADE_SHOP_POS):Length2D()
            _G.HeroMove = "[8loc] Moving to shop (" .. math.floor(distToShop) .. ")"
            _G.HeroAction = "[8loc] Upgrade: go to shop"
            if distToShop > 150 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, UPGRADE_SHOP_POS, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                upgradeStep = 1
            end
        elseif upgradeStep == 1 then
            -- Продаём shard (повтор до исчезновения из инвентаря)
            _G.HeroMove = "[8loc] At shop"
            _G.HeroAction = "[8loc] Selling shard"
            if now - lastActionTime < 0.8 then
                return
            end
            local shardName = HasTeammate() and SHARD_NAME_TEAM or SHARD_NAME_SOLO
            local shard = nil
            for i = 0, 8 do
                local it = NPC.GetItemByIndex(h, i)
                if it and Ability.GetName(it) == shardName then
                    shard = it
                    break
                end
            end
            if shard then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_SELL_ITEM, nil, Vector(0,0,0), shard, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastActionTime = now
            else
                upgradeStep = 2
            end
        elseif upgradeStep == 2 then
            _G.HeroMove = "[8loc] At shop"
            _G.HeroAction = "[8loc] Moving boss_soul to slot"
            if now - lastActionTime < 0.8 then
                return
            end
            local soul = nil
            local soulSlot = -1
            for i = 0, 8 do
                local it = NPC.GetItemByIndex(h, i)
                if it then
                    if Ability.GetName(it) == BOSS_SOUL then
                        soul = it
                        soulSlot = i
                        break
                    end
                end
            end
            if not soul then
                upgradeStep = 3
                return
            end
            if soulSlot > 5 then
                local targetSlot = -1
                for i = 0, 5 do
                    local checkIt = NPC.GetItemByIndex(h, i)
                    if not checkIt then
                        targetSlot = i
                        break
                    end
                end
                if targetSlot == -1 then
                    for i = 0, 5 do
                        local itIn = NPC.GetItemByIndex(h, i)
                        if itIn then
                            local inName = Ability.GetName(itIn):lower()
                            if not inName:find("dragon_lance") then
                                targetSlot = i
                                break
                            end
                        end
                    end
                end
                if targetSlot ~= -1 then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, targetSlot, Vector(0,0,0), soul, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastActionTime = now
                    upgradeStep = 3
                end
            else
                upgradeStep = 3
            end
        elseif upgradeStep == 3 then
            _G.HeroMove = "[8loc] At shop"
            _G.HeroAction = "[8loc] Buying dragon_lance"
            if now - lastActionTime < 0.5 then
                return
            end
            if not quickBuySet then
                local dlName = HasTeammate() and DL3_NAME_TEAM or DL3_NAME_SOLO
                Engine.SetQuickBuy(dlName, true)
                quickBuySet = true
                return
            end
            Engine.ExecuteCommand("dota_purchase_quickbuy")
            local soulStillExists = false
            for i = 0, 8 do
                local it = NPC.GetItemByIndex(h, i)
                if it then
                    if Ability.GetName(it) == BOSS_SOUL then
                        soulStillExists = true
                        break
                    end
                end
            end
            if not soulStillExists then
                upgradeStep = 4
                lastActionTime = now
            end
        elseif upgradeStep == 4 then
            _G.HeroMove = "[8loc] At shop"
            _G.HeroAction = "[8loc] Sorting backpack items"
            if now - lastActionTime < 0.6 then
                return
            end
            local movedSomething = false
            for bp = 6, 8 do
                local itBackpack = NPC.GetItemByIndex(h, bp)
                if itBackpack then
                    for act = 0, 5 do
                        local itActiveCheck = NPC.GetItemByIndex(h, act)
                        if not itActiveCheck then
                            Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, act, Vector(0,0,0), itBackpack, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                            lastActionTime = now
                            movedSomething = true
                            break
                        end
                    end
                end
                if movedSomething then
                    break
                end
            end
            if not movedSomething then
                upgradeStep = 5
            end
        end
    elseif upgradeStep == 5 then
        local targetWp = WAYPOINTS[currentWpIndex]
        _G.HeroMove = "[8loc] Patrol WP" .. currentWpIndex .. "/" .. #WAYPOINTS
        _G.HeroAction = "[8loc] Searching enemies"

        -- Поиск всех врагов в радиусе 600 + босс в 1400
        local activeBoss = nil
        local priorityEnemy = nil
        local priorityDist = 601
        local closestEnemy = nil
        local closestDist = 601
        local allNPCs = NPCs.GetAll()
        
        for i = 1, #allNPCs do
            local npc = allNPCs[i]
            if npc and Entity.IsAlive(npc) and not Entity.IsSameTeam(h, npc) and not Entity.IsDormant(npc) then
                local npcPos = Entity.GetAbsOrigin(npc)
                local distToMe = (myPos - npcPos):Length2D()
                local name = NPC.GetUnitName(npc) or ""
                
                if name == BOSS_NAME and distToMe <= 1400 then
                    activeBoss = npc
                    bossSpawned = true
                elseif UNIT_NAMES[name] and distToMe <= 600 then
                    if name == "npc_dota_zone_7_unit_2" then
                        if distToMe < priorityDist then
                            priorityDist = distToMe
                            priorityEnemy = npc
                        end
                    end
                    if distToMe < closestDist then
                        closestDist = distToMe
                        closestEnemy = npc
                    end
                end
            end
        end

        -- Босс убит → переход фазы
        if bossSpawned and activeBoss == nil then
            _G.GlobalPhase = 11
            return
        end

        -- Clean expired puddles
        for idx, puddle in pairs(activePuddles) do
            if now - puddle.created > GOO_MAX_LIFETIME then
                activePuddles[idx] = nil
            end
        end

        -- Dodge goo puddles (priority over attacking)
        local dangerPuddle = nil
        for _, puddle in pairs(activePuddles) do
            if puddle.pos then
                if (myPos - puddle.pos):Length2D() < puddle.radius + 30 then
                    dangerPuddle = puddle
                    break
                end
            end
        end

        if dangerPuddle then
            _G.HeroMove = "[8loc] Dodging goo"
            _G.HeroAction = "[8loc] Escaping acid (r" .. dodgeRotation .. ")"

            -- Anti-stuck: if hero barely moved while dodging, rapidly try next angle
            if lastDodgePos and (myPos - lastDodgePos):Length2D() < 20 then
                if dodgeStuckStart == 0 then dodgeStuckStart = now end
                if now - dodgeStuckStart > 0.35 then
                    dodgeRotation = dodgeRotation + 1
                    if dodgeRotation > 11 then dodgeRotation = 0 end
                    dodgeStuckStart = now
                end
            else
                dodgeStuckStart = 0
            end
            lastDodgePos = myPos

            local escapePos = FindSafeEscapePos(myPos, activePuddles, activeBoss, dangerPuddle.pos, dangerPuddle.radius, dodgeRotation)

            if now - lastMove >= moveDelay then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, escapePos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                lastMove = now
            end
            return
        else
            dodgeStuckStart = 0
            dodgeRotation = 0
            lastDodgePos = nil
        end

        local currentTarget = activeBoss or priorityEnemy or closestEnemy

        -- ЛОГИКА ДЕЙСТВИЙ
        if currentTarget then
            local tName = (NPC.GetUnitName(currentTarget) or ""):gsub("npc_dota_", "")
            _G.HeroMove = "[8loc] In combat"
            _G.HeroAction = "[8loc] ATK: " .. tName
            if now - lastActionTime >= 0.2 then
                Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, currentTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                local knifeItem = GetKnives(h)
                if knifeItem and Ability.IsReady(knifeItem) then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0,0,0), knifeItem, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                end
                lastActionTime = now
            end
        else
            -- ДВИЖЕНИЕ ПО ВЕЙПОИНТАМ
            local distToDest = (myPos - targetWp):Length2D()

            -- Non-Medusa в команде: следует позади Медузы (75 юнитов назад)
            if HasTeammate() and not IsMedusa(h) then
                local medusa = FindTeammateMedusa()
                if medusa and Entity.IsAlive(medusa) and not Entity.IsDormant(medusa) then
                    local medusaPos = Entity.GetAbsOrigin(medusa)
                    local dir = (targetWp - medusaPos):Normalized()
                    local behindPos = medusaPos - dir * 75
                    local distToBehind = (myPos - behindPos):Length2D()
                    _G.HeroMove = "[8loc] Behind Medusa (" .. math.floor(distToBehind) .. ")"
                    _G.HeroAction = "[8loc] Following"
                    if distToBehind > 50 and now - lastMove >= moveDelay then
                        Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, behindPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                        lastMove = now
                    end
                    local medusaWP = EstimateMedusaWaypoint(medusaPos)
                    if medusaWP > 0 then currentWpIndex = math.max(1, medusaWP) end
                    return
                end
            end

            if distToDest > 40 then
                if now - lastMove >= moveDelay then
                    Player.PrepareUnitOrders(pMe, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetWp, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, h)
                    lastMove = now
                end
            else
                currentWpIndex = currentWpIndex + 1
                if currentWpIndex > #WAYPOINTS then
                    currentWpIndex = 1
                end
            end
        end
    end
end

function script.OnDraw()
    if _G.GlobalPhase ~= 10 then return end
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

function script.OnParticleCreate(prt)
    if not prt then return end
    local name = prt.name or ""
    if name:find("alchemist_acid_spray") then
        activePuddles[prt.index] = {
            pos = nil,
            radius = 300,
            created = os.clock()
        }
    end
end

function script.OnParticleUpdate(prt)
    if not prt then return end
    local puddle = activePuddles[prt.index]
    if not puddle then return end
    local cp = prt.controlPoint
    local pos = prt.position
    if not pos then return end
    if cp == 0 then
        puddle.pos = pos
    elseif cp == 1 then
        if pos.x and pos.x > 50 then
            puddle.radius = pos.x
        end
    end
end

function script.OnParticleDestroy(prt)
    if not prt then return end
    if activePuddles[prt.index] then
        activePuddles[prt.index] = nil
    end
end

return script