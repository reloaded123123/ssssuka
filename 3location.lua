local script = {}

-- Глобальная таблица снарядов, пойманных через OnLinearProjectileCreate
-- Ключ: имя NPC-источника (zone_2_trap_X), значение: список handle снарядов
local trap_proj_pending = {}

-- Данные партикл-трекинга лазерного луча
-- Заполняются через OnParticleCreate / OnParticleUpdate
local laser_beam_particle = {
    index  = nil,
    cp     = {},
    angle  = nil,
    center = nil,
    tip    = nil,
    updated = 0,
}

-- Точные параметры ловушек из server-side start_logic.lua
local TRAP_BURST_DATA = {
    zone_2_trap_1 = { shots = 3, interval = 0.3, cooldown = 1.7 },
    zone_2_trap_2 = { shots = 2, interval = 0.2, cooldown = 0.8 },
    zone_2_trap_3 = { shots = 3, interval = 0.3, cooldown = 1.0 },
    zone_2_trap_4 = { shots = 3, interval = 0.3, cooldown = 1.8 },
    zone_2_trap_5 = { shots = 1, interval = 0.3, cooldown = 1.5 },
    zone_2_trap_6 = { shots = 2, interval = 0.3, cooldown = 1.2 },
    zone_2_trap_7 = { shots = 1, interval = 0.5, cooldown = 0.5 },
    zone_2_trap_8 = { shots = 2, interval = 0.3, cooldown = 1.5 },
    zone_2_trap_9 = { shots = 2, interval = 0.3, cooldown = 1.7 },
}

-- =============================================================================
-- ЗАДЕРЖКИ ПО ИНДЕКСУ WAYPOINT (для повторяющихся ловушек — разные значения)
-- =============================================================================
local WAYPOINT_POST_DELAYS = {
    [1]  = 0.38,   -- trap1
    [2]  = 0.30,   -- trap2
    [3]  = 0.68,   -- trap3 (увеличено, чтобы точно ждал все 3 снаряда)
    [5]  = 0.55,   -- trap4
    [6]  = 0.18,   -- trap5 (1)
    [7]  = 1.2,   -- trap5 (2)
    [8]  = 1.2,   -- trap5 (3 + лазер)
    [9]  = 0.40,   -- trap5 (4)
    [11] = 0.80,   -- trap6 (1)
    [12] = 0.25,   -- trap7
    [13] = 0.50,   -- trap6 (2)
    [15] = 0.50,   -- trap6 (3)
    [16] = 0.36,   -- trap8
    [19] = 0.55,   -- trap9
}

local DEFAULT_WAYPOINT_DELAY = 0.30

-- Параметры безопасности
local LASER_RADIUS = 355
local LASER_DANGER_ZONE = 350
local SAFE_ORBIT = 360
local MIN_LASER_DIST = 135
local FIRST_LASER_MIN_DIST = 200
local LOOK_AHEAD_TIME = 1.5
local PING_COMPENSATION = 50
local LOG_ACTIONS = true

-- АДАПТИВНАЯ СИСТЕМА ДЛЯ ЛОВУШЕК
local last_frame_times = {}
local function GetDynamicPing()
    local now = os.clock()
    table.insert(last_frame_times, now)
    if #last_frame_times > 10 then
        table.remove(last_frame_times, 1)
    end
    local avg_frame_time = 0
    if #last_frame_times > 1 then
        for i = 2, #last_frame_times do
            avg_frame_time = avg_frame_time + (last_frame_times[i] - last_frame_times[i-1])
        end
        avg_frame_time = avg_frame_time / (#last_frame_times - 1)
    end
    local base_ping = PING_COMPENSATION
    local fps_factor = math.max(0, (avg_frame_time - 0.016) * 1000)
    local estimated_ping = base_ping + fps_factor
    return math.max(20, math.min(300, estimated_ping))
end

local function GetAdaptiveDelay(base_delay, trap_type)
    local ping = GetDynamicPing()
    local ping_factor = ping / 100.0
    local adaptive_delay = base_delay
    if ping > 80 then
        adaptive_delay = base_delay + (ping_factor * 0.15)
    elseif ping > 150 then
        adaptive_delay = base_delay + (ping_factor * 0.25)
    end
    if trap_type == "zone_2_trap_1" then
        adaptive_delay = adaptive_delay + 0.08
    elseif trap_type == "zone_2_trap_8" then
        adaptive_delay = adaptive_delay + 0.12
    elseif trap_type == "zone_2_trap_6" then
        adaptive_delay = adaptive_delay + 0.06
    end
    return math.max(0.05, adaptive_delay)
end

local function IsPathSafeFromTraps(start_pos, target_pos)
    local projs = LinearProjectiles.GetAll()
    if not projs or #projs == 0 then return true end
    local path_vec = target_pos - start_pos
    local path_len = path_vec:Length2D()
    for i = 0, 5 do
        local progress = i / 5
        local check_pos = start_pos + path_vec * progress
        for _, p in ipairs(projs) do
            local p_pos = p['origin'] or p['position']
            if p_pos then
                local dist_to_proj = (check_pos - p_pos):Length2D()
                if dist_to_proj < 150 then
                    return false
                end
            end
        end
    end
    return true
end

local NARROW_PASSAGE_ANGLE_DEG = 55
function script.IsPointInNarrowPassage(l_pos, point, stand_pos)
    if not l_pos or not stand_pos or not point then return false end
    local to_stand = math.atan2(stand_pos.y - l_pos.y, stand_pos.x - l_pos.x) * 180 / math.pi
    local to_point = math.atan2(point.y - l_pos.y, point.x - l_pos.x) * 180 / math.pi
    local diff = math.abs(to_point - to_stand)
    while diff > 180 do diff = 360 - diff end
    return diff < NARROW_PASSAGE_ANGLE_DEG
end

-- =============================================================================
-- ПЕРЕРАБОТАННЫЙ ПЕРВЫЙ ЛАЗЕР — БЕЗ КАСАНИЯ ЛУЧА НИКОГДА
-- =============================================================================
function script.IsFirstLaserPathSafe(stand_pos, target_pos, l_pos, laser_yaw, omega)
    if not stand_pos or not target_pos or not l_pos or not laser_yaw then return false end

    local me = Heroes.GetLocal()
    local speed = NPC.GetMoveSpeed(me) or 300
    local pvx = target_pos.x - stand_pos.x
    local pvy = target_pos.y - stand_pos.y
    local path_len = math.sqrt(pvx*pvx + pvy*pvy)
    local travel_time = path_len / speed

    local STARTUP_DELAY = 0.24
    local laser_yaw_at_start = laser_yaw + omega * STARTUP_DELAY
    local omega_safe = omega * 1.28
    local omega_abs = math.abs(omega_safe)

    local beam_half = (omega_abs > 90 and 19 or (omega_abs > 70 and 14 or 24)) + 36

    -- Усиленный запас именно для CW (лог показывает CW)
    local extra_margin = 0
    if omega > 3 then extra_margin = extra_margin + 18 end      -- CW
    if omega_abs < 60 then extra_margin = extra_margin + 16 end -- медленно
    local effective_beam_half = beam_half + extra_margin

    local tlx = l_pos.x - stand_pos.x
    local tly = l_pos.y - stand_pos.y
    local proj_t = (tlx*pvx + tly*pvy) / (path_len*path_len)
    proj_t = math.max(0, math.min(1, proj_t))
    local cx = stand_pos.x + proj_t * pvx
    local cy = stand_pos.y + proj_t * pvy
    local closest_dist = math.sqrt((cx-l_pos.x)^2 + (cy-l_pos.y)^2)

    if closest_dist >= LASER_RADIUS then return true end

    local t_crit = proj_t * travel_time
    local laser_at_crit = laser_yaw_at_start + omega_safe * t_crit
    local angle_crit = math.atan2(cy - l_pos.y, cx - l_pos.x) * 180 / math.pi
    local diff_crit = math.abs(angle_crit - laser_at_crit)
    while diff_crit > 180 do diff_crit = math.abs(diff_crit - 360) end
    if diff_crit < effective_beam_half then return false end

    for i = 1, 13 do
        local progress = i / 14
        local px = stand_pos.x + progress * pvx
        local py = stand_pos.y + progress * pvy
        local dx = px - l_pos.x
        local dy = py - l_pos.y
        local dist_sq = dx*dx + dy*dy
        if dist_sq < (LASER_RADIUS + 42) * (LASER_RADIUS + 42) then
            local t = progress * travel_time
            local laser_at_t = laser_yaw_at_start + omega_safe * t
            local angle_to_pt = math.atan2(dy, dx) * 180 / math.pi
            local diff = math.abs(angle_to_pt - laser_at_t)
            while diff > 180 do diff = math.abs(diff - 360) end
            if diff < effective_beam_half then return false end
        end
    end

    return true
end

local function GetAdaptiveLaserParams(omega_abs, laser_type)
    local base_margin = 70
    local base_reaction = 0.2
    local base_tail = 120
    
    if omega_abs > 90 then
        base_margin = 185
        base_reaction = 0.78
        base_tail = 320
    elseif omega_abs > 70 then
        base_margin = 140
        base_reaction = 0.48
        base_tail = 240
    elseif omega_abs > 45 then
        base_margin = 92
        base_reaction = 0.36
        base_tail = 180
    end
    
    if laser_type == "first" then
        if omega_abs < 70 then
            base_margin = math.floor(base_margin * 0.9)
            base_reaction = base_reaction * 0.9
        else
            base_margin = math.floor(base_margin * 1.15)
            base_reaction = base_reaction * 1.28
        end
    elseif laser_type == "wall" then
        base_margin = math.floor(base_margin * 0.85)
        base_reaction = base_reaction * 0.85
    elseif laser_type == "fourth" then
        base_margin = math.floor(base_margin * 0.8)
        base_reaction = base_reaction * 0.8
    end
    
    return {
        margin = base_margin,
        reaction = base_reaction,
        tail = base_tail
    }
end

local traps_logic = {
    waypoints = {
        { stand = Vector(-8073, -2514, 640), target = Vector(-7520, -1888, 640), trap_name = "zone_2_trap_1", count = 3, delay = 0.12 },
        { stand = Vector(-7520, -1888, 640), target = Vector(-7832, -1346, 640), trap_name = "zone_2_trap_2", count = 2, delay = 0.1 },
        { stand = Vector(-7832, -1346, 640), target = Vector(-8117, -1124, 640), trap_name = "zone_2_trap_3", count = 3, delay = 0.115 },
        
        { stand = Vector(-8117, -1124, 640), target = Vector(-8032, -352, 640), laser_name = "npc_dota_first_circle_trap", move_while_cutting = true },
        { stand = Vector(-8032, -352, 640), target = Vector(-8186, 228, 640), trap_name = "zone_2_trap_4", count = 3, delay = 0.1 },
        
        { stand = Vector(-8186, 228, 640), target = Vector(-8488, -37, 640), trap_name = "zone_2_trap_5", count = 1, delay = 0.0 },
        { stand = Vector(-8488, -37, 640), target = Vector(-8895, -42, 640), trap_name = "zone_2_trap_5", count = 1, delay = 0.0 },
        
        { stand = Vector(-8895, -42, 640), target = Vector(-9255, -294, 640), trap_name = "zone_2_trap_5", count = 1, laser_name = "npc_dota_first_circle_trap", need_cut_tree = true, ignore_laser_dist = 450, delay = 0.05, skip_tail_avoid = true },
        
        { stand = Vector(-9255, -294, 640), target = Vector(-9312, -864, 768), trap_name = "zone_2_trap_5", count = 1, delay = 0.0 },
        
        { stand = Vector(-9312, -864, 768), target = Vector(-10087, -1415, 640), laser_name = "npc_dota_first_circle_trap" },
        
        { stand = Vector(-10087, -1415, 640), target = Vector(-10393, -1432, 640), trap_name = "zone_2_trap_6", count = 2, delay = 0.0 },
        { stand = Vector(-10393, -1432, 640), target = Vector(-10599, -1421, 640), trap_name = "zone_2_trap_7", count = 4, delay = 0.0 },
        { stand = Vector(-10599, -1421, 640), target = Vector(-11443, -1020, 771), trap_name = "zone_2_trap_6", count = 2, delay = 0.15 },
        { stand = Vector(-11443, -1020, 771), target = Vector(-11326, -1029, 768), is_plate_step = true, max_plate_counts = 13 },
        { stand = Vector(-10843, -1433, 646), target = Vector(-10146, 176, 640), trap_name = "zone_2_trap_6", count = 2, delay = 0.0 },
        { stand = Vector(-10146, 176, 640), target = Vector(-10617, 158, 640), trap_name = "zone_2_trap_8", count = 2, delay = 0.1 },
        
        { stand = Vector(-10617, 158, 640), target = Vector(-11006, -183, 640), laser_name = "npc_dota_first_circle_trap" },
        
        { stand = Vector(-11006, -183, 640), target = Vector(-11414, -79, 640) },
        { stand = Vector(-11744, -865, 640), target = Vector(-11943, -869, 640), need_cut_tree = true },
        { stand = Vector(-11943, -869, 640), target = Vector(-12569, -949, 640), trap_name = "zone_2_trap_9", count = 2, use_ability = true, delay = 0.0, immediate_next = true },
        { stand = Vector(-12569, -949, 640), }
    },
    current_idx = 1,
    trap_data = {
        current_burst_ids = {}, passed_count = 0, finish_time = 0, last_proj_time = 0,
        is_aborting = false, plate_count = 0, on_way_to_target = false,
        tree_attempted = false, last_yaw = nil, omega = 0, omega_samples = nil, last_update = 0,
        last_tree_cut = 0, wait_until = 0, last_move_pos = Vector(0,0,0),
        stuck_timer = 0, last_pos = nil, force_move_time = 0, last_frame_time = 0,
        orbit_start_time = 0, wait_start_time = 0, ability_used = false, stuck_move_attempts = 0,
        first_laser_wait_start = 0, all_passed_time = 0, proj_min_dist = {},
        burst_first_time = nil, burst_complete_time = nil,
        cooldown_seen = false, trap_start_time = nil
    }
}

local traversalCompleted = false

local function GetGlobalPhase()
    if _G and _G.GlobalPhase ~= nil then return _G.GlobalPhase end
    return GlobalPhase
end

local function SetGlobalPhase(v)
    if _G then _G.GlobalPhase = v end
    GlobalPhase = v
end

function script.OnUpdate()
    if GetGlobalPhase() ~= 3 then return end

    if traversalCompleted then
        SetGlobalPhase(4)
        return
    end

    local me = Heroes.GetLocal()
    if not me or not Entity.IsAlive(me) then return end
    
    local my_pos = Entity.GetAbsOrigin(me)
    local wp = traps_logic.waypoints[traps_logic.current_idx]
    if not wp then
        traversalCompleted = true
        return
    end

    local now = os.clock()
    local d = traps_logic.trap_data
    local current_idx = traps_logic.current_idx

    if current_idx == 4 then
        local movement_threshold = 30
        if d.last_pos and (my_pos - d.last_pos):Length2D() < movement_threshold then
            d.stuck_timer = (d.stuck_timer or 0) + (now - (d.last_frame_time or now))
        else
            d.stuck_timer = 0
        end
        d.last_pos = my_pos
        d.last_frame_time = now
        
        if (d.stuck_timer or 0) > 3.0 then
            d.force_move_time = now + 2.0
            d.stuck_timer = 0
        end
    end

    if wp.laser_name then
        script.UpdateLaserOmega(wp, d, now, current_idx)
    end

    if current_idx == 8 and not d.wait_start_time then
        d.wait_start_time = 0
    elseif current_idx == 10 and not d.wait_start_time then
        d.wait_start_time = 0
    end

    if wp.need_cut_tree and not d.tree_attempted then
        local path_vec = wp.target - wp.stand
        local path_dir = path_vec:Normalized()
        local path_len = path_vec:Length2D()
        local trees_on_path = {}
        
        for i = 1, 20 do
            local t = i / 20
            local check_pos = wp.stand + path_dir * (path_len * t)
            local near_trees = Trees.InRadius(check_pos, 200, true)
            if near_trees and #near_trees > 0 then
                for _, tree in ipairs(near_trees) do
                    table.insert(trees_on_path, tree)
                end
            end
        end
        
        local target_trees = Trees.InRadius(wp.target, 250, true)
        if target_trees and #target_trees > 0 then
            for _, tree in ipairs(target_trees) do
                table.insert(trees_on_path, tree)
            end
        end
        
        if #trees_on_path > 0 then
            local cutter = script.GetCullingItem(me)
            if cutter then
                Player.PrepareUnitOrders(Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, Entity.GetIndex(trees_on_path[1]), Vector(0,0,0), cutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUED_BY_PLAYER, me)
                d.tree_attempted = true
                if wp.move_while_cutting then
                    script.Move(me, wp.target)
                end
            end
        else
            d.tree_attempted = true
        end
    end

    if wp.is_plate_step then
        if d.plate_count < wp.max_plate_counts then
            if not d.on_way_to_target then
                if (my_pos - wp.target):Length2D() > 50 then script.Move(me, wp.target) else d.on_way_to_target = true end
            else
                if (my_pos - wp.stand):Length2D() > 50 then script.Move(me, wp.stand) else d.plate_count = d.plate_count + 1 d.on_way_to_target = false end
            end
            return
        else
            traps_logic.current_idx = traps_logic.current_idx + 1
            script.ResetData()
            return
        end
    end

    if d.finish_time > 0 then
        local dist_to_target = (my_pos - wp.target):Length2D()
        
        local required_distance = 75
        if current_idx == 4 then
            required_distance = 100
        elseif current_idx == 10 then
            required_distance = 90
        elseif current_idx == 16 then
            required_distance = 85
        end
        
        if dist_to_target < required_distance then
            traps_logic.current_idx = traps_logic.current_idx + 1
            script.ResetData()
            return
        end
        
        if current_idx == 10 and d.finish_time > 0 then
            local time_in_movement = now - d.finish_time + 0.05
            if time_in_movement > 10.0 then
                traps_logic.current_idx = traps_logic.current_idx + 1
                script.ResetData()
                return
            end
        end

        if wp.use_ability and not d.ability_used then
            local dist_to_target = (my_pos - wp.target):Length2D()
            if dist_to_target <= 100 then
                local first_ability = NPC.GetAbilityByIndex(me, 0)
                if first_ability and Ability.IsReady(first_ability) then
                    Ability.CastNoTarget(first_ability)
                    d.ability_used = true
                    if LOG_ACTIONS then
                        Log.Write(string.format("[USE ABILITY] Used %s", Ability.GetName(first_ability)))
                    end
                else
                    for i = 0, 5 do
                        local ability = NPC.GetAbilityByIndex(me, i)
                        if ability and Ability.IsReady(ability) then
                            Ability.CastNoTarget(ability)
                            d.ability_used = true
                            break
                        end
                    end
                end
                
                if d.ability_used and wp.immediate_next then
                    traps_logic.current_idx = traps_logic.current_idx + 1
                    script.ResetData()
                    return
                elseif not d.ability_used and wp.immediate_next then
                    traps_logic.current_idx = traps_logic.current_idx + 1
                    script.ResetData()
                    return
                end
            end
        end
        
        if wp.laser_name then
            local should_cut = true
            if should_cut and now - d.last_tree_cut > 0.3 then
                local near_trees = Trees.InRadius(my_pos, 280, true)
                if near_trees and #near_trees > 0 then
                    local cutter = script.GetCullingItem(me)
                    if cutter then
                        Player.PrepareUnitOrders(Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE, Entity.GetIndex(near_trees[1]), Vector(0,0,0), cutter, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUED_BY_PLAYER, me)
                        d.last_tree_cut = now
                    end
                end
            end

            local laser = script.FindLaser(wp.stand, wp.laser_name, wp.ignore_laser_dist)
            local move_goal = wp.target
            if laser then
                local l_pos = Entity.GetAbsOrigin(laser)
                local cur_yaw = Entity.GetRotation(laser):GetYaw()
                
                if current_idx == 4 then
                    local beam_yaw = cur_yaw
                    if laser_beam_particle.angle and (os.clock() - laser_beam_particle.updated) < 0.5 then
                        beam_yaw = laser_beam_particle.angle
                    end
                    local dist_to_laser = (my_pos - l_pos):Length2D()
                    local reactive_abort = false

                    -- РАННИЙ ОТСКОК ПРИ 30° (чтобы никогда не касаться)
                    if dist_to_laser < LASER_RADIUS + 25 then
                        local pos_angle = math.atan2(my_pos.y - l_pos.y, my_pos.x - l_pos.x) * 180 / math.pi
                        local adiff = math.abs(pos_angle - beam_yaw)
                        while adiff > 180 do adiff = math.abs(adiff - 360) end
                        if adiff < 30 then
                            reactive_abort = true
                            move_goal = wp.stand
                            d.finish_time = 0
                            d.first_laser_wait_start = 0
                            if LOG_ACTIONS then
                                Log.Write(string.format("[FIRST LASER] EARLY ABORT: beam %.1f° (never touch)", adiff))
                            end
                        end
                    end
                    if not reactive_abort then
                        move_goal = wp.target
                    end
                else
                    local is_currently_safe = true
                    local dist_to_l = (my_pos - l_pos):Length2D()
                    if dist_to_l < LASER_DANGER_ZONE then
                        is_currently_safe = not script.IsPositionInDangerZone(my_pos, l_pos, cur_yaw, d.omega, current_idx)
                    end
                    local path_check_duration = wp.skip_tail_avoid and 1.2 or 0.7
                    if math.abs(d.omega) > 70 then path_check_duration = path_check_duration + 0.8 end
                    local is_path_safe = script.IsPathSafeFromPos(my_pos, wp.target, l_pos, cur_yaw, d.omega, path_check_duration, wp.laser_name, current_idx)
                    local is_too_close = wp.skip_tail_avoid and (dist_to_l < MIN_LASER_DIST)
                    
                    if wp.skip_tail_avoid or current_idx == 8 or current_idx == 10 or current_idx == 16 then
                        if current_idx == 8 or current_idx == 10 or current_idx == 16 then
                            local dist_to_target = (my_pos - wp.target):Length2D()
                            local required_dist = 100
                            if current_idx == 8 then required_dist = 80
                            elseif current_idx == 10 then required_dist = 120
                            elseif current_idx == 16 then required_dist = 100
                            end
                            if dist_to_target < required_dist then
                                traps_logic.current_idx = traps_logic.current_idx + 1
                                script.ResetData()
                                return
                            end
                        end
                        
                        if is_too_close then
                            local escape_dir = (my_pos - l_pos):Normalized()
                            if current_idx == 16 then
                                local trap_8_pos = Vector(-10146, 176, 640)
                                local escape_pos = my_pos + escape_dir * 100
                                local dist_to_trap8 = (escape_pos - trap_8_pos):Length2D()
                                if dist_to_trap8 < 200 then
                                    local to_target_dir = (wp.target - my_pos):Normalized()
                                    move_goal = my_pos + to_target_dir * 80
                                else
                                    move_goal = escape_pos
                                end
                            else
                                move_goal = my_pos + escape_dir * 100
                            end
                        end
                    elseif (not is_currently_safe or not is_path_safe) and current_idx ~= 4 then
                        local laser_type = "normal"
                        if current_idx == 16 then laser_type = "fourth" end
                        local params = GetAdaptiveLaserParams(math.abs(d.omega), laser_type)
                        local offset = (d.omega > 0) and params.tail or -params.tail
                        local safe_yaw = cur_yaw + offset
                        local rad = safe_yaw * math.pi / 180
                        local safe_orbit = math.max(SAFE_ORBIT, (params.tail or 0) + 50)
                        move_goal = l_pos + Vector(math.cos(rad) * safe_orbit, math.sin(rad) * safe_orbit, 0)
                    else
                        d.orbit_start_time = 0
                    end
                end
            end

            script.Move(me, move_goal)
        else
            script.Move(me, wp.target)
        end
        return
    end

    if (my_pos - wp.stand):Length2D() > 45 then
        script.Move(me, wp.stand)
        return
    end

    if traps_logic.current_idx == #traps_logic.waypoints and not wp.target and not wp.trap_name and not wp.laser_name then
        Player.PrepareUnitOrders(Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_STOP, nil, Vector(0,0,0), nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUED_BY_PLAYER, me)
        traversalCompleted = true
        return
    end

    local traps_ready = true
    if wp.trap_name and wp.count then
        traps_ready = script.TrackSpecificProjectiles(me, wp, d, now, current_idx)
    end

    if traps_ready then
        local laser_ready = true
        if wp.laser_name then
            local laser = script.FindLaser(wp.stand, wp.laser_name, wp.ignore_laser_dist)
            if laser then
                local l_pos = Entity.GetAbsOrigin(laser)
                if (wp.stand - l_pos):Length2D() < (wp.ignore_laser_dist or 850) then
                    if math.abs(d.omega) > 0.01 then
                        local is_stand_safe = true
                        local dist_stand_to_l = (wp.stand - l_pos):Length2D()
                        if dist_stand_to_l < LASER_DANGER_ZONE then
                            is_stand_safe = not script.IsPositionInDangerZone(wp.stand, l_pos, d.last_yaw, d.omega, current_idx)
                        end
                        
                        local sim_time = LOOK_AHEAD_TIME
                        if current_idx == 4 then
                            sim_time = LOOK_AHEAD_TIME + 1.8
                        elseif math.abs(d.omega) > 70 then
                            sim_time = LOOK_AHEAD_TIME + 1.0
                        end
                        local is_path_safe = script.IsPathSafeFromPos(wp.stand, wp.target, l_pos, d.last_yaw, d.omega, sim_time, wp.laser_name, current_idx)
                        
                        if current_idx == 4 then
                            if (d.first_laser_wait_start or 0) == 0 then
                                d.first_laser_wait_start = now
                            end
                            local wait_time = now - d.first_laser_wait_start
                            
                            local path_is_safe = script.IsFirstLaserPathSafe(wp.stand, wp.target, l_pos, d.last_yaw, d.omega)
                            
                            local omega_abs = math.abs(d.omega)
                            local max_wait_time = (360.0 / omega_abs) + 1.0
                            if max_wait_time < 4.0 then max_wait_time = 4.0 end
                            if max_wait_time > 11.0 then max_wait_time = 11.0 end

                            if d.omega < 0 and omega_abs < 60 then
                                max_wait_time = max_wait_time + 1.5
                            end

                            if LOG_ACTIONS and math.floor(wait_time * 2) % 2 == 0 then
                                local direction = d.omega > 0 and "CW" or "CCW"
                                local speed_cat = omega_abs > 90 and "very_fast" or
                                                 omega_abs > 70 and "fast" or
                                                 omega_abs > 45 and "medium" or "slow"
                                Log.Write(string.format("[FIRST LASER] Wait %.1f/%.1fs, %s %s, path safe: %s",
                                    wait_time, max_wait_time, speed_cat, direction,
                                    tostring(path_is_safe)))
                            end
                            
                            if path_is_safe or wait_time > max_wait_time then
                                laser_ready = true
                                d.finish_time = now + 0.05
                                if LOG_ACTIONS then 
                                    if path_is_safe then
                                        Log.Write("[FIRST LASER] PATH CLEAR - DASH TO TARGET!")
                                    else
                                        Log.Write(string.format("[FIRST LASER] Timeout %.1fs - forcing passage", wait_time))
                                    end
                                end
                            else
                                laser_ready = false
                            end
                        elseif current_idx == 8 then
                            laser_ready = is_stand_safe and is_path_safe
                            if laser_ready then
                                d.finish_time = now + 0.05
                            else
                                local safe_window = script.FindSafePassageWindow(wp.stand, wp.target, l_pos, d.last_yaw, d.omega, current_idx)
                                if safe_window >= 0 and safe_window < 2.0 then
                                    if safe_window <= 0.05 then
                                        laser_ready = true
                                        d.finish_time = now + 0.05
                                    else
                                        laser_ready = false
                                    end
                                else
                                    if (d.wait_start_time or 0) == 0 then
                                        d.wait_start_time = now
                                    end
                                    local waiting_time = now - d.wait_start_time
                                    if waiting_time > 8.0 then
                                        laser_ready = true
                                        d.finish_time = now + 0.05
                                    else
                                        laser_ready = false
                                    end
                                end
                            end
                        elseif current_idx == 10 then
                            if math.abs(d.omega) < 50 then
                                local current_safe = not script.IsPositionInDangerZone(wp.stand, l_pos, d.last_yaw, d.omega, current_idx)
                                local path_safe = script.IsPathSafeFromPos(wp.stand, wp.target, l_pos, d.last_yaw, d.omega, 3.0, wp.laser_name, current_idx)
                                if current_safe and path_safe then
                                    laser_ready = true
                                    d.finish_time = now + 0.05
                                else
                                    laser_ready = false
                                    if (d.wait_start_time or 0) == 0 then
                                        d.wait_start_time = now
                                    end
                                    local waiting_time = now - d.wait_start_time
                                    if waiting_time > 15.0 then
                                        laser_ready = true
                                        d.finish_time = now + 0.05
                                    end
                                end
                            else
                                laser_ready = is_stand_safe and is_path_safe
                                if laser_ready then
                                    d.finish_time = now + 0.05
                                else
                                    local safe_window = script.FindSafePassageWindow(wp.stand, wp.target, l_pos, d.last_yaw, d.omega, current_idx)
                                    if safe_window >= 0 and safe_window < 1.5 then
                                        if safe_window <= 0.05 then
                                            laser_ready = true
                                            d.finish_time = now + 0.05
                                        else
                                            laser_ready = false
                                        end
                                    else
                                        if (d.wait_start_time or 0) == 0 then
                                            d.wait_start_time = now
                                        end
                                        local waiting_time = now - d.wait_start_time
                                        if waiting_time > 6.0 then
                                            laser_ready = true
                                            d.finish_time = now + 0.05
                                        else
                                            laser_ready = false
                                        end
                                    end
                                end
                            end
                        else
                            laser_ready = is_stand_safe and is_path_safe
                            if laser_ready then
                                laser_ready = true
                            else
                                local safe_window = script.FindSafePassageWindow(wp.stand, wp.target, l_pos, d.last_yaw, d.omega, current_idx)
                                if safe_window >= 0 and safe_window < 3.0 then
                                    if safe_window <= 0.1 then
                                        laser_ready = true
                                    else
                                        laser_ready = false
                                    end
                                else
                                    if (d.wait_start_time or 0) == 0 then
                                        d.wait_start_time = now
                                    end
                                    local waiting_time = now - d.wait_start_time
                                    if waiting_time > 12.0 then
                                        laser_ready = true
                                    else
                                        laser_ready = false
                                    end
                                end
                            end
                        end
                    else
                        laser_ready = false
                    end
                end
            end
        end

        if laser_ready then
            d.finish_time = now + 0.05
            script.Move(me, wp.target)
            if LOG_ACTIONS then
                Log.Write(string.format("[GO] All projectiles cleared from %s, running to target!", wp.trap_name or "unknown"))
            end
        end
    end
end

function script.GetCullingItem(me)
    for i = 0, 15 do
        local it = NPC.GetItemByIndex(me, i)
        if it and Ability.IsReady(it) then
            local n = Ability.GetName(it):lower()
            if n:find("quelling") or n:find("bfury") or n:find("tango") or n:find("battle_fury") then return it end
        end
    end
    return nil
end

function script.IsPositionInDangerZone(pos, l_pos, laser_yaw, omega, current_idx)
    local dist_to_l = (pos - l_pos):Length2D()
    local safe_dist = (current_idx == 4) and FIRST_LASER_MIN_DIST or MIN_LASER_DIST
    if dist_to_l < safe_dist then return true end
    if dist_to_l > LASER_RADIUS then return false end
    
    local pos_angle = math.atan2(pos.y - l_pos.y, pos.x - l_pos.x) * 180 / math.pi
    local current_laser_direction = laser_yaw
    local angle_diff = math.abs(pos_angle - current_laser_direction)
    while angle_diff > 180 do angle_diff = 360 - angle_diff end
    
    local laser_beam_width = 15
    if current_idx == 4 then
        laser_beam_width = 36
    elseif math.abs(omega) < 50 then
        laser_beam_width = 48
    elseif math.abs(omega) > 90 then
        laser_beam_width = 36
    elseif math.abs(omega) > 70 then
        laser_beam_width = 28
    end
    
    if angle_diff < laser_beam_width then
        return true
    end
    return false
end

function script.IsPathSafeFromPos(start_pos, end_pos, l_pos, cur_yaw, omega, duration, laser_name, current_idx)
    if not l_pos or not cur_yaw then return true end
    local me = Heroes.GetLocal()
    local speed = NPC.GetMoveSpeed(me)
    local path_vec = end_pos - start_pos
    local path_len = path_vec:Length2D()
    local path_time = path_len / speed
    local check_time = path_time
    if current_idx == 4 and duration and duration > path_time then
        check_time = duration
    end

    local check_points = math.max(14, math.floor(path_len / 40))
    
    for i = 0, check_points do
        local t = (i / check_points) * check_time
        local progress = math.min(i / check_points, 1.0)
        local check_pos = start_pos + path_vec * progress
        local future_laser_yaw = cur_yaw + (omega * t)
        if script.IsPositionInDangerZone(check_pos, l_pos, future_laser_yaw, omega, current_idx) then
            return false
        end
    end
    return true
end

function script.FindSafePassageWindow(start_pos, end_pos, l_pos, cur_yaw, omega, current_idx)
    if not l_pos or not cur_yaw or math.abs(omega) < 0.01 then return 0 end
    local me = Heroes.GetLocal()
    local speed = NPC.GetMoveSpeed(me)
    local path_len = (end_pos - start_pos):Length2D()
    local path_time = path_len / speed
    
    local check_duration = 8
    local check_step = 0.1
    local check_points_per_path = 8
    local buffer_time = (math.abs(omega) < 50) and 0.5 or 0.2
    
    if current_idx == 4 then
        check_step = 0.05
        check_points_per_path = 18
        buffer_time = (math.abs(omega) > 70) and 0.35 or 0.45
    elseif math.abs(omega) < 50 then
        check_duration = 12
        check_step = 0.05
        check_points_per_path = 15
    end
    
    for check_delay = 0, check_duration, check_step do
        local future_yaw = cur_yaw + (omega * check_delay)
        local path_safe = true
        
        for i = 0, check_points_per_path do
            local progress = i / check_points_per_path
            local check_pos = start_pos + (end_pos - start_pos) * progress
            local time_at_point = check_delay + (path_time * progress)
            local laser_yaw_at_point = cur_yaw + (omega * time_at_point)
            local buffered_yaw = laser_yaw_at_point + (omega * buffer_time)
            
            if script.IsPositionInDangerZone(check_pos, l_pos, laser_yaw_at_point, omega, current_idx) or
               script.IsPositionInDangerZone(check_pos, l_pos, buffered_yaw, omega, current_idx) then
                path_safe = false
                break
            end
        end
        
        if path_safe then
            return check_delay
        end
    end
    return -1
end

function script.UpdateLaserOmega(wp, d, now, current_idx)
    local laser = script.FindLaser(wp.stand, wp.laser_name, wp.ignore_laser_dist)
    if not laser then return end
    
    local cur_yaw = Entity.GetRotation(laser):GetYaw()
    if laser_beam_particle.angle and (os.clock() - laser_beam_particle.updated) < 0.3 then
        cur_yaw = laser_beam_particle.angle
    end
    if d.last_yaw then
        local dt = now - d.last_update
        if dt > 0 and dt < 0.5 then
            local diff = cur_yaw - d.last_yaw
            while diff > 180 do diff = diff - 360 end
            while diff < -180 do diff = diff + 360 end
            
            local new_omega = diff / dt
            if d.omega_samples then
                table.insert(d.omega_samples, new_omega)
                if #d.omega_samples > 5 then
                    table.remove(d.omega_samples, 1)
                end
                local sorted = {table.unpack(d.omega_samples)}
                table.sort(sorted)
                d.omega = sorted[math.ceil(#sorted/2)]
            else
                d.omega_samples = {new_omega}
                d.omega = new_omega
            end
        end
    end
    d.last_yaw, d.last_update = cur_yaw, now
end

local function GetRunDelayForCurrentWaypoint(current_idx)
    local delay = WAYPOINT_POST_DELAYS[current_idx]
    if delay then
        return delay
    end
    if LOG_ACTIONS then
        Log.Write("[DELAY] Нет задержки для waypoint #" .. current_idx .. " → дефолт " .. DEFAULT_WAYPOINT_DELAY)
    end
    return DEFAULT_WAYPOINT_DELAY
end

function script.TrackSpecificProjectiles(me, wp, d, now, current_idx)
    if not d.trap_start_time then d.trap_start_time = now end
    if not d.proj_min_dist then d.proj_min_dist = {} end

    local info = TRAP_BURST_DATA[wp.trap_name]
    local shots_per_burst = info and info.shots or 1
    local burst_inter = info and info.interval or 0.30
    local burst_cool = info and info.cooldown or 1.50
    local total_shots = wp.count

    local silence = d.last_proj_time > 0 and (now - d.last_proj_time) or (now - d.trap_start_time)
    local COOLDOWN_GAP = burst_cool * 0.60

    local RUN_BUFFER = GetRunDelayForCurrentWaypoint(current_idx)

    local function add_shot(id)
        if script.TableContains(d.current_burst_ids, id) then return end
        if #d.current_burst_ids == 0 then d.burst_first_time = now end
        table.insert(d.current_burst_ids, id)
        d.last_proj_time = now
        if LOG_ACTIONS then
            local phase = d.cooldown_seen and "ACT" or "SYNC"
            Log.Write(string.format("[TRAP %s][%s] Shot #%d", wp.trap_name, phase, #d.current_burst_ids))
        end
    end

    local pending = trap_proj_pending[wp.trap_name]
    if pending and #pending > 0 then
        for _, id in ipairs(pending) do add_shot(id) end
        trap_proj_pending[wp.trap_name] = {}
    end

    if #d.current_burst_ids < total_shots then
        local trap_ent = script.FindEnt(wp.trap_name)
        if trap_ent then
            local trap_pos = Entity.GetAbsOrigin(trap_ent)
            local trap_spawn_radius = 80
            local max_proj_dist = 200
            
            for _, p in ipairs(LinearProjectiles.GetAll()) do
                local p_pos = p['origin'] or p['position']
                if p_pos and p['handle'] then
                    local dist_from_trap = (p_pos - trap_pos):Length2D()
                    if dist_from_trap < max_proj_dist then
                        if dist_from_trap < trap_spawn_radius then
                            add_shot(p['handle'])
                        else
                            local other_trap_closer = false
                            for other_name, _ in pairs(TRAP_BURST_DATA) do
                                if other_name ~= wp.trap_name then
                                    local other_ent = script.FindEnt(other_name)
                                    if other_ent then
                                        local other_pos = Entity.GetAbsOrigin(other_ent)
                                        local dist_to_other = (p_pos - other_pos):Length2D()
                                        if dist_to_other < dist_from_trap - 30 then
                                            other_trap_closer = true
                                            break
                                        end
                                    end
                                end
                            end
                            if not other_trap_closer then
                                add_shot(p['handle'])
                            end
                        end
                    end
                end
            end
        end
    end

    if shots_per_burst > 1 and not d.cooldown_seen then
        if silence >= COOLDOWN_GAP then
            d.cooldown_seen = true
            d.current_burst_ids = {}
            d.proj_min_dist = {}
            d.burst_first_time = nil
            d.burst_complete_time = nil
            trap_proj_pending[wp.trap_name] = {}
            if LOG_ACTIONS then
                Log.Write(string.format("[TRAP %s] SYNC OK: cooldown seen", wp.trap_name))
            end
        elseif LOG_ACTIONS and math.floor(now) % 2 == 0 then
            Log.Write(string.format("[TRAP %s] SYNC: shots=%d, silence=%.2f/%.2fs", wp.trap_name, #d.current_burst_ids, silence, COOLDOWN_GAP))
        end
        return false
    end

    if #d.current_burst_ids == 0 then
        if LOG_ACTIONS and math.floor(now) % 2 == 0 then
            Log.Write(string.format("[TRAP %s] ACT: waiting for burst...", wp.trap_name))
        end
        return false
    end

    if not d.burst_complete_time then
        local all_fired = #d.current_burst_ids >= total_shots
        local inferred = false
        if not all_fired and shots_per_burst > 1 and d.burst_first_time then
            local expected_end = d.burst_first_time + burst_inter * (total_shots - 1) + 0.25
            inferred = (now > expected_end)
            if not inferred and (now - d.burst_first_time) > (burst_inter * total_shots + 0.5) then
                inferred = true
            end
        end

        if all_fired or inferred then
            d.burst_complete_time = now
            if LOG_ACTIONS then
                local reason = all_fired and "registered" or "timing"
                Log.Write(string.format("[TRAP %s] ACT: %d shots (%s) → wait %.2fs buffer", wp.trap_name, math.min(#d.current_burst_ids, total_shots), reason, RUN_BUFFER))
            end
        else
            if LOG_ACTIONS and math.floor(now * 2) % 2 == 0 then
                local time_since_first = d.burst_first_time and (now - d.burst_first_time) or 0
                local expected_remaining = burst_inter * (total_shots - #d.current_burst_ids)
                Log.Write(string.format("[TRAP %s] ACT: %d/%d shots (wait ~%.2fs)", wp.trap_name, #d.current_burst_ids, total_shots, expected_remaining))
            end
            return false
        end
    end

    local elapsed = now - d.burst_complete_time
    if elapsed < RUN_BUFFER then
        if LOG_ACTIONS and math.floor(now * 4) % 2 == 0 then
            Log.Write(string.format("[TRAP %s] ACT: buffer %.2f/%.2fs", wp.trap_name, elapsed, RUN_BUFFER))
        end
        return false
    end

    if LOG_ACTIONS then
        Log.Write(string.format("[TRAP %s] Buffer passed → RUN!", wp.trap_name))
    end
    return true
end

function script.TableContains(t, v)
    for _, val in ipairs(t) do if val == v then return true end end
    return false
end

function script.FindProjByHandle(h)
    for _, p in ipairs(LinearProjectiles.GetAll()) do
        if (p['handle'] or _) == h then return p end
    end
    return nil
end

function script.ResetData()
    trap_proj_pending = {}
    traps_logic.trap_data = {
        current_burst_ids = {}, passed_count = 0, finish_time = 0, last_proj_time = 0,
        is_aborting = false, plate_count = 0, on_way_to_target = false,
        tree_attempted = false, last_yaw = nil, omega = 0, omega_samples = nil, last_update = 0,
        last_tree_cut = 0, wait_until = 0, last_move_pos = Vector(0,0,0),
        stuck_timer = 0, last_pos = nil, force_move_time = 0, last_frame_time = 0,
        orbit_start_time = 0, wait_start_time = 0, ability_used = false, stuck_move_attempts = 0,
        first_laser_wait_start = 0, all_passed_time = 0, proj_min_dist = {},
        burst_first_time = nil, burst_complete_time = nil,
        cooldown_seen = false, trap_start_time = nil
    }
end

function script.OnLinearProjectileCreate(proj)
    if not proj then return end
    local src = proj.source
    if not src or not Entity.IsNPC(src) then return end
    local src_name = NPC.GetUnitName(src)
    if not src_name then return end
    
    local current_wp = traps_logic.waypoints[traps_logic.current_idx]
    if not current_wp or not current_wp.trap_name then return end
    
    if not string.find(src_name, "zone_2_trap_") and src_name ~= "npc_dota_simple_trap" then return end
    
    local trap_name = src_name
    if src_name == "npc_dota_simple_trap" then
        local src_pos = Entity.GetAbsOrigin(src)
        local best_name, best_dist = nil, 300
        for name, _ in pairs(TRAP_BURST_DATA) do
            local ent = script.FindEnt(name)
            if ent then
                local dist = (Entity.GetAbsOrigin(ent) - src_pos):Length2D()
                if dist < best_dist then best_dist = dist; best_name = name end
            end
        end
        if not best_name then return end
        trap_name = best_name
    end
    
    if trap_name ~= current_wp.trap_name then
        return
    end
    
    if not trap_proj_pending[trap_name] then
        trap_proj_pending[trap_name] = {}
    end
    local id = proj.handle
    table.insert(trap_proj_pending[trap_name], id)
    if LOG_ACTIONS then
        Log.Write(string.format("[PROJ_CREATE] %s matched waypoint trap=%s", trap_name, current_wp.trap_name))
    end
end

function script.OnParticleCreate(prt)
    if not prt then return end
    local ent = prt.entity or prt.entityForModifiers
    if not ent or not Entity.IsNPC(ent) then return end
    local ent_name = NPC.GetUnitName(ent)
    if ent_name ~= "npc_dota_first_circle_trap" and ent_name ~= "npc_dota_circle_trap" then return end
    laser_beam_particle.index = prt.index
    laser_beam_particle.cp = {}
    laser_beam_particle.angle = nil
    laser_beam_particle.center = nil
    laser_beam_particle.tip = nil
    laser_beam_particle.updated = os.clock()
    if LOG_ACTIONS then
        Log.Write(string.format("[LASER_PARTICLE] Created idx=%s name=%s", tostring(prt.index), tostring(prt.name or "?")))
    end
end

function script.OnParticleUpdate(prt)
    if not prt then return end
    if laser_beam_particle.index == nil then return end
    if prt.index ~= laser_beam_particle.index then return end
    local cp = prt.controlPoint
    local pos = prt.position
    if not pos then return end
    laser_beam_particle.cp[cp] = pos
    laser_beam_particle.updated = os.clock()
    if cp == 0 then laser_beam_particle.center = pos end
    if cp == 1 then laser_beam_particle.tip = pos end
    if laser_beam_particle.center and laser_beam_particle.tip then
        local dx = laser_beam_particle.tip.x - laser_beam_particle.center.x
        local dy = laser_beam_particle.tip.y - laser_beam_particle.center.y
        if dx*dx + dy*dy > 100 then
            laser_beam_particle.angle = math.atan2(dy, dx) * 180 / math.pi
        end
    end
end

function script.FindLaser(pos, name, max_dist)
    local ents = Entities.GetAll()
    local best, min_d = nil, max_dist or 99999
    for _, e in ipairs(ents) do
        if e and Entity.GetUnitName(e) == name then
            if not pos then return e end
            local dist = (Entity.GetAbsOrigin(e) - pos):Length2D()
            if dist < min_d then
                min_d, best = dist, e
            end
        end
    end
    return best
end

function script.FindEnt(name)
    local ents = Entities.GetAll()
    for _, e in ipairs(ents) do
        if e and Entity.GetUnitName(e) == name then return e end
    end
    return nil
end

function script.Move(me, pos)
    if not pos then
        if LOG_ACTIONS then
            Log.Write("[MOVE] ERROR: pos is nil!")
        end
        return
    end

    local d = traps_logic.trap_data
    local current_idx = traps_logic.current_idx
    
    local dist_from_last = (d.last_move_pos - pos):Length2D()
    if dist_from_last < 40 then
        d.stuck_move_attempts = (d.stuck_move_attempts or 0) + 1
        if d.stuck_move_attempts > 5 then
            d.last_move_pos = Vector(0, 0, 0)
            d.stuck_move_attempts = 0
        else
            return
        end
    else
        d.stuck_move_attempts = 0
    end
    
    Player.PrepareUnitOrders(Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, pos, nil, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUED_BY_PLAYER, me)
    d.last_move_pos = pos
end

return script