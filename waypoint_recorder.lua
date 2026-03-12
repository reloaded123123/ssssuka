local module = {}

-- === КОНФИГУРАЦИЯ ===
local RECORD_KEY = Enum.ButtonCode.KEY_V      -- Нажми V чтобы записать вейпоинт
local PRINT_KEY = Enum.ButtonCode.KEY_P       -- Нажми P чтобы вывести все вейпоинты
local CLEAR_KEY = Enum.ButtonCode.KEY_C       -- Нажми C чтобы очистить список

-- === СОСТОЯНИЕ ===
local waypoints = {}
local recordedCount = 0

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

local function PrintAllWaypoints()
    if #waypoints == 0 then
        Log.Write("⚠️ Вейпоинты не записаны!")
        return
    end
    
    Log.Write("=" * 60)
    Log.Write("📍 ВСЕ ЗАПИСАННЫЕ ВЕЙПОИНТЫ (" .. #waypoints .. " штук)")
    Log.Write("=" * 60)
    
    local result = "local waypoints = {"
    for i, wp in ipairs(waypoints) do
        local line = string.format("    Vector(%.0f, %.0f, %.0f),   -- WP %d", wp.x, wp.y, wp.z, i)
        Log.Write(line)
        result = result .. "\n" .. line
    end
    result = result .. "\n}"
    
    Log.Write("=" * 60)
    Log.Write("✅ Повтор для копирования выше ↑")
    Log.Write("=" * 60)
end

local function ClearWaypoints()
    waypoints = {}
    recordedCount = 0
    Log.Write("🗑️ Список вейпоинтов очищен!")
end

local function RecordWaypoint(pos)
    if not pos then
        Log.Write("❌ Позиция не найдена!")
        return
    end
    
    recordedCount = recordedCount + 1
    table.insert(waypoints, Vector(pos.x, pos.y, pos.z))
    
    Log.Write(string.format("✅ WP %d записан: Vector(%.0f, %.0f, %.0f)", 
        recordedCount, pos.x, pos.y, pos.z))
end

-- === ГЛАВНАЯ ФУНКЦИЯ ===

function module.OnUpdate()
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end
    
    local myPos = Entity.GetAbsOrigin(h)
end

function module.OnKeyEvent(data)
    local h = Heroes.GetLocal()
    if not h then return false end
    
    local myPos = Entity.GetAbsOrigin(h)
    
    -- ЗАПИСЬ ВЕЙПОИНТА
    if data.key == RECORD_KEY and data.event == Enum.EKeyEvent.KeyDown then
        RecordWaypoint(myPos)
        return true
    end
    
    -- ВЫВОД ВСЕХ ВЕЙПОИНТОВ
    if data.key == PRINT_KEY and data.event == Enum.EKeyEvent.KeyDown then
        PrintAllWaypoints()
        return true
    end
    
    -- ОЧИСТКА СПИСКА
    if data.key == CLEAR_KEY and data.event == Enum.EKeyEvent.KeyDown then
        ClearWaypoints()
        return true
    end
    
    return false
end

-- === ВОЗВРАТ МОДУЛЯ ===

return {
    OnUpdate = module.OnUpdate,
    OnKeyEvent = module.OnKeyEvent
}
