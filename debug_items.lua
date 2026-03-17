local script = {}

local lastPrintTime = 0
local PRINT_INTERVAL = 2.0

function script.OnUpdate()
    local myHero = Heroes.GetLocal()
    if not myHero then return end

    local now = os.clock()
    if now - lastPrintTime < PRINT_INTERVAL then return end
    lastPrintTime = now

    local myPos = Entity.GetAbsOrigin(myHero)
    if not myPos then return end

    local items = PhysicalItems.GetAll()
    if not items then
        print("[ITEMS_DBG] PhysicalItems.GetAll() вернул nil")
        return
    end

    local count = 0
    print("===== [ITEMS ON GROUND] =====")

    for _, item in pairs(items) do
        if item and not Entity.IsDormant(item) then
            local inner = PhysicalItem.GetItem(item)
            local itemName = inner and Ability.GetName(inner) or "???"
            local itemPos = Entity.GetAbsOrigin(item) or PhysicalItem.GetPosition(item)
            local dist = itemPos and math.floor((itemPos - myPos):Length2D()) or -1
            local x = itemPos and math.floor(itemPos.x) or 0
            local y = itemPos and math.floor(itemPos.y) or 0
            local z = itemPos and math.floor(itemPos.z) or 0

            print(string.format("  [%s] dist=%d pos=(%d, %d, %d)", itemName, dist, x, y, z))
            count = count + 1
        end
    end

    if count == 0 then
        print("  Предметов на земле нет.")
    else
        print(string.format("  Всего: %d", count))
    end
    print("=============================")
end

return script
