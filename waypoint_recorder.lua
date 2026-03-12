-- WAYPOINT RECORDER - ЗАПИСЬ ПО БИНДУ
local waypoints = {}
local RECORD_KEY = Enum.ButtonCode.KEY_F6
local shownHint = false

local function RecordCurrentPosition(hero)
    local pos = Entity.GetAbsOrigin(hero)
    local x = math.floor(pos.x + 0.5)
    local y = math.floor(pos.y + 0.5)
    local z = math.floor(pos.z + 0.5)

    table.insert(waypoints, { x = x, y = y, z = z })
    Log.Write(string.format("WP %d: Vector(%d, %d, %d)", #waypoints, x, y, z))
end

local function OnUpdate()
    local h = Heroes.GetLocal()
    if not h or not Entity.IsAlive(h) then return end

    if not shownHint then
        Log.Write("Waypoint Recorder: нажми F6, чтобы записать текущую позицию героя")
        shownHint = true
    end

    if Input.IsInputCaptured() then return end

    -- Сработает один раз за нажатие клавиши
    if Input.IsKeyDownOnce(RECORD_KEY) then
        RecordCurrentPosition(h)
    end
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
    else
        Log.Write("Waypoint Recorder: маршрут пуст, ни одной точки не записано")
    end
end

return {
    OnUpdate = OnUpdate,
    OnGameEnd = OnGameEnd
}
