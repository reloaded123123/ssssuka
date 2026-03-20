local monitor = {}

if _G == nil then _G = {} end
if _G.GlobalPhase == nil then _G.GlobalPhase = 1 end

local last_restart_file_time = 0
local last_cam_check = 0
local last_stuck_pos = nil
local last_stuck_time = 0
local last_level_check_time = 0

local level_21_created = false
local level_25_created = false

local function run_ahk_script()
    if os.clock() - last_restart_file_time < 10.0 then
        return
    end

    local f = io.open("C:\\dota_auto\\scripts\\restart.please", "w")
    if f then 
        f:close() 
        last_restart_file_time = os.clock()
        _G.GlobalPhase = 1 
        level_21_created = false
        level_25_created = false
        last_stuck_pos = nil
        last_stuck_time = 0
        print("[MONITOR] restart.please создан.")
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
            local f, err = io.open("C:\\dota_auto\\21.please", "w")
            if f then
                f:write("21")
                f:close()
                level_21_created = true 
                print("[MONITOR] 21.please создан.")
            else
                print("[MONITOR] ОШИБКА 21.please: " .. tostring(err))
            end
        end

        if not level_25_created and spent >= 27 then
            local f, err = io.open("C:\\dota_auto\\25.please", "w")
            if f then
                f:write("25")
                f:close()
                level_25_created = true 
                print("[MONITOR] 25.please создан.")
            else
                print("[MONITOR] ОШИБКА 25.please: " .. tostring(err))
            end
        end

        if spent >= 20 then
            print("[MONITOR] spent=" .. spent .. " 21_created=" .. tostring(level_21_created) .. " 25_created=" .. tostring(level_25_created))
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