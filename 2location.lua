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
    Vector(-7591, -8625, 512), Vector(-8163, -7628, 512), Vector(-8712, -6994, 512),
    Vector(-9806, -5593, 512), Vector(-10616, -5822, 512), Vector(-11810, -5379, 512),
    Vector(-12805, -5235, 512), Vector(-11910, -6782, 512), Vector(-12893, -7878, 384),
    Vector(-13827, -7388, 384), Vector(-14352, -4895, 384), Vector(-15090, -6866, 384),
    Vector(-15256, -5172, 384), Vector(-15552, -8385, 512), Vector(-10962, -8312, 512),
    Vector(-10036, -7284, 512), -- 22
    Vector(-8277, -4899, 384)   -- 23 (Босс)
}

local currentWP = 1
local lastMoveTime = 0

function script.OnUpdate()
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end

    local myPlayer = Players.GetLocal()
    if not myPlayer then return end

    local myPos = Entity.GetAbsOrigin(myHero)
    local now = os.clock()

    if currentWP > #WAYPOINTS_L2 then return end

    local targetPos = WAYPOINTS_L2[currentWP]

    -- 1. ПОИСК ЦЕЛЕЙ
    local allNPCs = NPCs.GetAll()
    local crateTarget = nil
    local bossTarget = nil
    local normalTarget = nil

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
                local bossSearchDist = (currentWP >= 23) and 1000 or 400
                if distToHero <= bossSearchDist then
                    bossTarget = npc
                end
            end

            -- Обычные мобы в радиусе 400
            if TARGET_UNITS[name] and distToHero <= 400 then
                normalTarget = npc
            end
        end
    end

    -- 2. ВЫБОР ЦЕЛИ (Босс теперь важнее обычных мобов)
    local activeTarget = crateTarget or bossTarget or normalTarget

    if activeTarget then
        Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET, activeTarget, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
        return
    end

    -- 3. ДВИЖЕНИЕ
    local distToWP = (myPos - targetPos):Length2D()

    if distToWP > 100 then
        if now - lastMoveTime > 0.3 then
            Player.PrepareUnitOrders(myPlayer, Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, targetPos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, myHero)
            lastMoveTime = now
        end
    else
        currentWP = currentWP + 1
    end
end

return script