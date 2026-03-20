--[[
    ОБНОВЛЕННЫЙ МОНИТОР (АБСОЛЮТНЫЙ ПУТЬ)
    Целевая папка: C:\dota_auto\scripts\
    Полный код без сокращений, согласно вашим правилам.
--]]

local monitor = {}

-- Инициализация глобальных переменных в окружении чита
if _G == nil then _G = {} end
if _G.GlobalPhase == nil then _G.GlobalPhase = 1 end

-- ЖЕСТКО ЗАДАННЫЙ ПУТЬ (Убедитесь, что папка создана заранее)
local TARGET_PATH = "C:\\dota_auto\\scripts\\"

-- Переменные для отслеживания состояний и таймингов
local last_restart_trigger = 0
local last_camera_update = 0
local last_pos_snapshot = nil
local last_move_timestamp = 0
local last_level_process_time = 0

-- Флаги однократного срабатывания для уровней
local is_level_21_sent = false
local is_level_25_sent = false

-- Вспомогательная функция для безопасного создания файла по прямому пути
local function WriteSignalFile(name)
    local full_path = TARGET_PATH .. name
    -- Попытка открыть файл в режиме "w" (перезапись/создание)
    local file, err = io.open(full_path, "w")
    
    if file then
        -- Записываем проверочную информацию
        file:write("signal_active: " .. os.date("%H:%M:%S"))
        file:flush()
        file:close()
        print("[MONITOR] Успех! Файл создан: " .. full_path)
        return true
    else
        -- Если здесь снова Permission denied, значит права на папку C:\dota_auto\scripts не настроены
        print("[MONITOR] КРИТИЧЕСКАЯ ОШИБКА ДОСТУПА: " .. tostring(err))
        return false
    end
end

-- Функция инициализации рестарта (взаимодействие с AHK)
local function TriggerRestart()
    local current_clock = os.clock()
    
    -- Ограничение: не чаще одного раза в 10 секунд
    if current_clock - last_restart_trigger < 10.0 then
        return
    end

    if WriteSignalFile("restart.please") then
        last_restart_trigger = current_clock
        _G.GlobalPhase = 1 
        print("[MONITOR] Сигнал RESTART отправлен в " .. TARGET_PATH)
    end
end

-- Функция принудительного фокуса камеры на герое
local function CameraLock()
    if os.clock() - last_camera_update > 2.0 then
        Engine.ExecuteCommand("+dota_camera_follow")
        last_camera_update = os.clock()
    end
end

function monitor.OnUpdate()
    -- Получаем объект локального игрока
    local me = Heroes.GetLocal()
    if not me then return end

    local now = os.clock()

    -- 1. Выполнение логики камеры
    CameraLock()

    -- 2. Логика проверки уровней прокачки (раз в 2 сек)
    if (now - last_level_process_time) > 2.0 then
        last_level_process_time = now
        
        local total_spent = 0
        -- Перебор всех способностей и талантов (индексы 0-31)
        for i = 0, 31 do
            local ability = NPC.GetAbilityByIndex(me, i)
            if ability then
                local level = Ability.GetLevel(ability)
                -- Суммируем только числовые значения уровней
                if level and type(level) == "number" and level > 0 then 
                    total_spent = total_spent + level 
                end
            end
        end

        -- Условие для 21 уровня (сумма очков >= 25)
        if not is_level_21_sent and total_spent >= 25 then
            if WriteSignalFile("21.please") then
                is_level_21_sent = true 
            end
        end

        -- Условие для 25 уровня (сумма очков >= 27)
        if not is_level_25_sent and total_spent >= 27 then
            if WriteSignalFile("25.please") then
                is_level_25_sent = true 
            end
        end
    end

    -- 3. Рестарт при смерти
    if not Entity.IsAlive(me) then
        TriggerRestart()
        return
    end

    -- 4. Проверка на застревание (Анти-АФК)
    local current_pos = Entity.GetAbsOrigin(me)
    if not last_pos_snapshot then 
        last_pos_snapshot = current_pos 
        last_move_timestamp = now 
    end

    -- Сравниваем текущую позицию с предыдущим снимком
    if (current_pos - last_pos_snapshot):Length() > 150 then
        -- Если герой прошел больше 150 юнитов, обновляем данные
        last_pos_snapshot = current_pos
        last_move_timestamp = now
    else
        -- Если герой стоит на месте дольше 120 секунд
        if now - last_move_timestamp > 120 then
            print("[MONITOR] Детектор застревания сработал. Рестарт...")
            TriggerRestart()
        end
    end
    
    -- 5. Проверка глобального флага завершения игры
    if _G.GlobalPhase == "FINISHED" then
        TriggerRestart()
    end
end

-- Возвращаем таблицу для регистрации колбэков в чите
return monitor