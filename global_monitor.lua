local monitor = {}

if _G == nil then _G = {} end
if _G.GlobalPhase == nil then _G.GlobalPhase = 1 end

local last_restart_file_time = 0
local last_cam_check = 0
local last_stuck_pos = nil
local last_stuck_time = 0
local last_level_check_time = 0

-- Таймеры в памяти
local log_time_21 = 0
local log_time_25 = 0
local log_time_restart = 0

local level_21_created = false
local level_25_created = false

-- Функция записи в разные файлы
local function WriteToSeparateLog(filename, source_name)
    local path = "C:\\dota_auto\\" .. filename
    local f = io.open(path, "a")
    if f then
        local me = Heroes.GetLocal()
        f:write("\n[" .. os.date("%H:%M:%S") .. "] --- LOG [" .. source_name .. "] ---\n")
        if me then
            for i = 0, 8 do
                local it = NPC.GetItemByIndex(me, i)
                local name = it and Ability.GetName(it) or "Empty"
                f:write("Slot " .. i .. ": " .. name .. "\n")
            end
        else
            f:write("Hero not found\n")
        end
        f:write("------------------------------------\n")
        f:flush()
        f:close()
        print("[MONITOR] Данные записаны в " .. filename)
    end
end

local function run_ahk_script()
    if os.clock() - last_restart_file_time < 10.0 then
        return
    end

    local f = io.open("C:\\dota_auto\\restart.please", "w")
    if f then 
        f:close() 
        last_restart_file_time = os.clock()
        _G.GlobalPhase = 1 
        -- ТАЙМЕР 70 СЕКУНД
        log_time_restart = os.time() + 100
        print("[MONITOR] restart.please создан. Лог будет через 70 сек.")
    end
end

local function CameraFollow()
    if os.clock() - last_cam_check > 2.0 then
        Engine.ExecuteCommand("+dota_camera_follow")
        last_cam_check = os.clock()
    end
end

function monitor.OnUpdate()
    local me = Heroes.GetLocal()
    if not me then return end

    local now_clock = os.clock()
    local now_time = os.time()

    -- ПРОВЕРКА ТАЙМЕРОВ
    if log_time_21 > 0 and now_time >= log_time_21 then
        WriteToSeparateLog("log_21.log", "LEVEL 21")
        log_time_21 = 0
    end
    if log_time_25 > 0 and now_time >= log_time_25 then
        WriteToSeparateLog("log_25.log", "LEVEL 25")
        log_time_25 = 0
    end
    if log_time_restart > 0 and now_time >= log_time_restart then
        WriteToSeparateLog("log_restart.log", "RESTART EVENT")
        log_time_restart = 0
    end

    CameraFollow()

    if (now_clock - last_level_check_time) > 2.0 then
        last_level_check_time = now_clock
        
        local spent = 0
        for i = 0, 31 do
            local abil = NPC.GetAbilityByIndex(me, i)
            if abil then
                local l = Ability.GetLevel(abil)
                if l and type(l) == "number" and l > 0 then 
                    spent = spent + l 
                end
            end
        end

        if not level_21_created and spent >= 25 then
            local f = io.open("C:\\dota_auto\\21.please", "w")
            if f then
                f:write("21")
                f:close()
                level_21_created = true 
                -- ТАЙМЕР 12 СЕКУНД
                log_time_21 = os.time() + 14
                print("[MONITOR] 21.please создан. Жду 12с.")
            end
        end

        if not level_25_created and spent >= 27 then
            local f = io.open("C:\\dota_auto\\25.please", "w")
            if f then
                f:write("25")
                f:close()
                level_25_created = true 
                -- ТАЙМЕР 12 СЕКУНД
                log_time_25 = os.time() + 14
                print("[MONITOR] 25.please создан. Жду 12с.")
            end
        end
    end

    if not Entity.IsAlive(me) then
        run_ahk_script()
        return
    end

    local my_pos = Entity.GetAbsOrigin(me)
    if not last_stuck_pos then 
        last_stuck_pos = my_pos 
        last_stuck_time = now_clock 
    end

    if (my_pos - last_stuck_pos):Length() > 100 then
        last_stuck_pos = my_pos
        last_stuck_time = now_clock
    else
        if now_clock - last_stuck_time > 120 then
            run_ahk_script()
        end
    end
    
    if _G.GlobalPhase == "FINISHED" then
        run_ahk_script()
    end
end

return monitor