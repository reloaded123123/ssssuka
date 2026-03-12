local debug_script = {}

-- Настройки дебага
local DEBUG_RADIUS = 500
local lastPrintTime = 0

function debug_script.OnUpdate()
    local myHero = Heroes.GetLocal()
    if not myHero then return end

    local now = os.clock()
    -- Выводим инфу раз в секунду, чтобы не засирать консоль бесконечным потоком
    if now - lastPrintTime < 1.0 then return end
    lastPrintTime = now

    local myPos = Entity.GetAbsOrigin(myHero)
    local allNPCs = NPCs.GetAll()
    
    print("--- [DEBUG AREA] Радиус 500 ---")
    local found = false

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        
        if npc and npc ~= myHero and Entity.IsAlive(npc) then
            local npcPos = Entity.GetAbsOrigin(npc)
            local dist = (npcPos - myPos):Length2D()

            if dist <= DEBUG_RADIUS then
                local name = NPC.GetUnitName(npc)
                local isEnemy = not Entity.IsSameTeam(myHero, npc)
                local teamText = isEnemy and "ВРАГ" or "СВОЙ"
                
                -- Пишем в консоль (~) имя, дистанцию и команду
                print(string.format("[%s] %s | Dist: %d", teamText, name, math.floor(dist)))
                found = true
            end
        end
    end

    if not found then
        print("В радиусе 500 никого нет.")
    end
end

return debug_script