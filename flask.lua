---@diagnostic disable: undefined-global

local Entity = Entity
local NPC = NPC
local Heroes = Heroes
local Players = Players
local Player = Player
local Ability = Ability
local Enum = Enum
local Vector = Vector

local bsa_final = {
    flask_logic = {
        is_active = true,       
        was_moved = false,      
        was_used = false,       
        move_time = 0,          
        original_slot = -1,     -- Слот, где была фласка (например, 6)
        finished = false,
        need_wait = false       
    },
    
    target_items = {
        "item_bkb_flask",
        "item_immune_flask"
    }
}

local function IsTargetItem(item)
    if not item then return false end
    local name = Ability.GetName(item)
    for _, target in ipairs(bsa_final.target_items) do
        if name == target then return true end
    end
    return false
end

function bsa_final.HandleFlask(me, p, hero_pos)
    local f = bsa_final.flask_logic
    
    if not f.is_active or f.finished then return end

    -- ЭТАП 1: ПЕРЕМЕЩЕНИЕ ФЛАСКИ В 0 СЛОТ
    if not f.was_moved then
        for i = 0, 8 do
            local it = NPC.GetItemByIndex(me, i)
            if it and IsTargetItem(it) then
                f.original_slot = i
                
                if i == 0 then
                    f.need_wait = false
                    print("[FLASK] Фласка уже в 0 слоте.")
                else
                    f.need_wait = (i >= 6) -- Если из ранца/тайника (6, 7, 8)

                    -- Свапаем фласку в 0 слот. То, что было в 0, улетает в i.
                    Player.PrepareUnitOrders(
                        p, 
                        Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 
                        0, 
                        Vector(0,0,0), 
                        it, 
                        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, 
                        me
                    )
                    print("[FLASK] Свап фласки из слота " .. i .. " в слот 0.")
                end
                
                f.was_moved = true
                f.move_time = os.clock()
                return
            end
        end
        f.finished = true 
        return
    end

    -- ЭТАП 2: ИСПОЛЬЗОВАНИЕ
    if f.was_moved and not f.was_used then
        local current_delay = os.clock() - f.move_time
        if not f.need_wait or current_delay > 6.55 then
            local fl = NPC.GetItemByIndex(me, 0)
            if fl and IsTargetItem(fl) then
                Ability.CastPosition(fl, hero_pos)
                print("[FLASK] Использовал фласку.")
                f.was_used = true
                f.move_time = os.clock()
            else
                -- Если фласка исчезла (использована)
                f.was_used = true
                f.move_time = os.clock()
            end
        end
    end

    -- ЭТАП 3: ВОЗВРАТ ПРЕДМЕТА НА МЕСТО И БЕГ
    if f.was_used and not f.finished then
        -- Ждем 0.5с, чтобы сервер точно зафиксировал, что фласки в 0 слоте больше нет
        if os.clock() - f.move_time > 0.5 then
            
            -- Если мы свапали (original_slot не 0)
            if f.original_slot > 0 then
                -- Мы берем ТО, ЧТО СЕЙЧАС ЛЕЖИТ в слоте, где раньше была фласка
                -- и перетаскиваем это в освободившийся слот 0.
                local item_in_old_slot = NPC.GetItemByIndex(me, f.original_slot)
                
                if item_in_old_slot then
                    Player.PrepareUnitOrders(
                        p, 
                        Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, 
                        0, -- Цель: слот 0
                        Vector(0,0,0), 
                        item_in_old_slot, -- Предмет, который улетел из 0 в 6
                        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, 
                        me
                    )
                    print("[FLASK] Вернул предмет из слота " .. f.original_slot .. " обратно в слот 0.")
                end
            end

            -- СРАЗУ ПОСЛЕ ЭТОГО БЕЖИМ
            Player.PrepareUnitOrders(
                p, 
                Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, 
                nil, 
                Vector(-11973, -1824, 640), 
                nil, 
                Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, 
                me
            )
            print("[FLASK] Идем к финишу Vector(-11973, -1824, 640).")
            
            f.finished = true
            f.is_active = false
        end
    end
end

return {
    OnUpdate = function()
        local me = Heroes.GetLocal()
        if not me or not Entity.IsAlive(me) then return end
        local p = Players.GetLocal()
        if not p then return end
        local hero_pos = Entity.GetAbsOrigin(me)
        if not hero_pos then return end

        bsa_final.HandleFlask(me, p, hero_pos)
    end
}