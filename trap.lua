---@diagnostic disable: undefined-global

local Vector = Vector
local Entity = Entity
local NPC = NPC
local Heroes = Heroes
local NPCs = NPCs
local Players = Players
local Player = Player

local PUSH_POS = {
    Vector(-11802, -2029, 640),   -- 1
    Vector(-11230, -1990, 640),   -- 2
    Vector(-11872, -2414, 640)    -- 3
}

local TARGET_PLATES = {
    Vector(-11589, -2302, 664),
    Vector(-11262, -2339, 664),
    Vector(-11535, -2623, 664)
}

local FINAL_PLATE = Vector(-11267, -2623, 664)

local POS_TOL = 70  
local PLATE_TOL = 70 
local ATTACK_INTERVAL = 0.8 

local solver = {
    hero = nil,
    player = nil,
    phase = 1,
    last_attack_time = 0,
    last_print = 0,
    target_box_handle = nil,
    is_positioned = false,
    done = false -- Мягкий стоп логики
}

local function GetGlobalPhase()
    if _G and _G.GlobalPhase ~= nil then return _G.GlobalPhase end
    return GlobalPhase
end

local function SetGlobalPhase(v)
    if _G then _G.GlobalPhase = v end
    GlobalPhase = v
end

local function Dist2D(p1, p2)
    if not p1 or not p2 then return 9999 end
    return (p1 - p2):Length2D()
end

local function IsBoxOnPlate(box_pos, plate_pos, range)
    if not box_pos or not plate_pos then return false end
    local bx, by = box_pos.x or box_pos:GetX(), box_pos.y or box_pos:GetY()
    local px, py = plate_pos.x or plate_pos:GetX(), plate_pos.y or plate_pos:GetY()
    return (math.abs(bx - px) <= range and math.abs(by - py) <= range)
end

local function find_target_box_handle(plate_pos)
    local closest = nil
    local min_d = math.huge
    for _, npc in ipairs(NPCs.GetAll() or {}) do
        if npc and NPC.GetUnitName(npc) == "npc_dota_crate2" then
            local pos = Entity.GetAbsOrigin(npc)
            if pos then
                local d = Dist2D(plate_pos, pos)
                if d < min_d then
                    min_d = d
                    closest = npc
                end
            end
        end
    end
    return closest
end

local function print_once(msg)
    local t = os.clock() or 0
    if t - solver.last_print > 2 then
        print(msg)
        solver.last_print = t
    end
end

return {
    OnScriptsLoaded = function()
        print("[PUZZLE] Скрипт запущен. После 4-й плиты управление вернется игроку.")
    end,

    OnUpdate = function()
        if GetGlobalPhase() ~= 5 then return end

        -- Если мы уже закончили — ничего не делаем
        if solver.done then return end

        solver.hero = Heroes.GetLocal()
        if not solver.hero then return end
        solver.player = Players.GetLocal()
        if not solver.player then return end
        local hero_pos = Entity.GetAbsOrigin(solver.hero)
        if not hero_pos then return end

        -- ФИНАЛЬНЫЙ ПЕРЕХОД
        if solver.phase == 4 then
            if Dist2D(hero_pos, FINAL_PLATE) > 50 then
                Player.PrepareUnitOrders(solver.player, 1, nil, FINAL_PLATE, nil, 2, solver.hero, false, false, false, false, nil, false)
            else
                -- Пришли, дали стоп и забыли
                Player.PrepareUnitOrders(solver.player, 8, nil, nil, nil, 2, solver.hero, false, false, false, false, nil, false)
                print("[DIAG] Финальная точка достигнута. Отключаюсь.")
                SetGlobalPhase(6)
                solver.done = true
            end
            return
        end

        local target_pos = PUSH_POS[solver.phase]
        local target_plate = TARGET_PLATES[solver.phase]

        -- 1. ПОЗИЦИОНИРОВАНИЕ
        if not solver.is_positioned then
            local d = Dist2D(hero_pos, target_pos)
            if d > POS_TOL then
                Player.PrepareUnitOrders(solver.player, 1, nil, target_pos, nil, 2, solver.hero, false, false, false, false, nil, false)
                return
            else
                Player.PrepareUnitOrders(solver.player, 8, nil, nil, nil, 2, solver.hero, false, false, false, false, nil, false)
                solver.is_positioned = true
                return
            end
        end

        -- 2. ВЫБОР ЯЩИКА
        if not solver.target_box_handle or not Entity.IsAlive(solver.target_box_handle) then
            solver.target_box_handle = find_target_box_handle(target_plate)
        end
        if not solver.target_box_handle then return end

        local box_pos = Entity.GetAbsOrigin(solver.target_box_handle)
        if not box_pos then return end

        -- 3. ПРОВЕРКА ПЛИТЫ
        if IsBoxOnPlate(box_pos, target_plate, PLATE_TOL) then
            print("[DIAG] Ящик фазы " .. solver.phase .. " на месте.")
            Player.PrepareUnitOrders(solver.player, 8, nil, nil, nil, 2, solver.hero, false, false, false, false, nil, false)
            solver.phase = solver.phase + 1
            solver.target_box_handle = nil
            solver.is_positioned = false
            return
        end

        -- 4. АТАКА И КОРРЕКЦИЯ
        local current_time = os.clock() or 0
        if current_time - solver.last_attack_time > ATTACK_INTERVAL then
            local dist_to_box = Dist2D(hero_pos, box_pos)

            if dist_to_box > 160 then
                local move_pos = hero_pos + (box_pos - hero_pos):Normalized() * (dist_to_box - 100)
                Player.PrepareUnitOrders(solver.player, 1, nil, move_pos, nil, 2, solver.hero, false, false, false, false, nil, false)
                return
            end

            Player.PrepareUnitOrders(solver.player, 8, nil, nil, nil, 2, solver.hero, false, false, false, false, nil, false)
            Player.PrepareUnitOrders(solver.player, 3, nil, box_pos, nil, 2, solver.hero, false, false, false, false, nil, false)
            solver.last_attack_time = current_time
        end
    end,
}