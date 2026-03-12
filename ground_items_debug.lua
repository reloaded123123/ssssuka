local ground_items_debug = {}

local PRINT_INTERVAL = 1.0
local DEBUG_RADIUS = 3000
local MAX_PRINT_ITEMS = 20
local lastPrintTime = 0

function ground_items_debug.OnUpdate()
    local me = Heroes.GetLocal()
    if not me or not Entity.IsAlive(me) then return end

    local now = os.clock()
    if now - lastPrintTime < PRINT_INTERVAL then return end
    lastPrintTime = now

    local myPos = Entity.GetAbsOrigin(me)
    local dropped = PhysicalItems.GetAll()

    if not dropped or #dropped == 0 then
        Log.Write("[GROUND ITEMS] На земле предметов нет")
        return
    end

    local nearby = {}

    for _, pItem in ipairs(dropped) do
        local item = PhysicalItem.GetItem(pItem)
        if item then
            local itemName = Ability.GetName(item)
            if not itemName or itemName == "" then
                itemName = "unknown_item"
            end

            local itemPos = Entity.GetAbsOrigin(pItem) or PhysicalItem.GetPosition(pItem)
            if itemPos then
                local dist = (itemPos - myPos):Length2D()
                if dist <= DEBUG_RADIUS then
                    table.insert(nearby, {
                        name = itemName,
                        dist = dist,
                        pos = itemPos,
                    })
                end
            end
        end
    end

    if #nearby == 0 then
        Log.Write(string.format("[GROUND ITEMS] В радиусе %.0f предметов нет", DEBUG_RADIUS))
        return
    end

    table.sort(nearby, function(a, b)
        return a.dist < b.dist
    end)

    Log.Write(string.format("[GROUND ITEMS] Найдено %d предметов в радиусе %.0f", #nearby, DEBUG_RADIUS))

    local limit = math.min(#nearby, MAX_PRINT_ITEMS)
    for i = 1, limit do
        local v = nearby[i]
        Log.Write(string.format(
            "[%d] %s | dist: %.0f | Vector(%.0f, %.0f, %.0f)",
            i,
            v.name,
            v.dist,
            v.pos.x,
            v.pos.y,
            v.pos.z
        ))
    end
end

return ground_items_debug
