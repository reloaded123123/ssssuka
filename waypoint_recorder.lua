-- WAYPOINT RECORDER - АВТОМАТИЧЕСКИЙ РЕЖИМ
local waypoints = {}
local lastRecordTime = 0
local RECORD_INTERVAL = 1.0  -- Записывать каждую 1 секунду
local lastPos = nil

local function OnUpdate()
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end
    
    local now = os.clock()
    local pos = Entity.GetAbsOrigin(h)
    
    -- Записываем вейпоинт каждую 1 секунду
    if now - lastRecordTime >= RECORD_INTERVAL then
        local x = math.floor(pos.x + 0.5)
        local y = math.floor(pos.y + 0.5)
        local z = math.floor(pos.z + 0.5)
        table.insert(waypoints, {x = x, y = y, z = z})
        Log.Write(string.format("📍 WP %d: Vector(%d, %d, %d)", #waypoints, x, y, z))
        lastRecordTime = now
    end
    
    lastPos = pos
end

local function OnGameEnd()
    if #waypoints > 0 then
        Log.Write("\n\n=== ПОЛНЫЙ МАРШРУТ ===")
        Log.Write("local waypoints = {")
        for i, wp in ipairs(waypoints) do
            Log.Write(string.format("    Vector(%d, %d, %d),  -- WP %d", wp.x, wp.y, wp.z, i))
        end
        Log.Write("}")
        Log.Write("=== КОНЕЦ ===\n\n")
    end
end

return {
    OnUpdate = OnUpdate,
    OnGameEnd = OnGameEnd
}
