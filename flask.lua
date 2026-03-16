---@diagnostic disable: undefined-global

local Entity = Entity
local NPC = NPC
local Heroes = Heroes
local Players = Players
local Player = Player
local Ability = Ability
local Enum = Enum
local Vector = Vector

local FINISH_POS = Vector(-11973, -1824, 640)

local PHASE_ID = 4
local NEXT_PHASE_ID = 5

local bsa_final = {
    flask_logic = {
        is_active = true,       
        was_moved = false,      
        was_used = false,       
        move_time = 0,          
        original_slot = -1,     -- Слот, где была фласка (например, 6)
        finished = false,
        finish_move_ordered = false,
        need_wait = false,
        axe_processed = false
    },
    
    target_items = {
        "item_bkb_flask",
        "item_immune_flask"
    }
}

local axe_items = {
    ["item_quelling_blade"] = true,
    ["item_bfury"] = true,
    ["item_battlefury"] = true
}

local function GetGlobalPhase()
    if _G and _G.GlobalPhase ~= nil then return _G.GlobalPhase end
    return GlobalPhase
end

local function SetGlobalPhase(v)
    if _G then _G.GlobalPhase = v end
    GlobalPhase = v
end

local function IsTargetItem(item)
    if not item then return false end
    local name = Ability.GetName(item)
    for _, target in ipairs(bsa_final.target_items) do
        if name == target then return true end
    end
    return false
end

local function IsAxeItem(item)
    if not item then return false end
    local name = Ability.GetName(item)
    return name and axe_items[name] or false
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

    -- ЭТАП 3: ВОЗВРАТ ПРЕДМЕТА НА МЕСТО
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

            f.axe_processed = false
            f.move_time = os.clock()
            return
        end
    end

    -- ЭТАП 4: ПОСЛЕ ФЛАСКИ КЛАДЕМ ТОПОРИК В СВОБОДНЫЙ СЛОТ РАНЦА
    if f.was_used and not f.finished and not f.axe_processed then
        if os.clock() - f.move_time > 0.2 then
            local axeHandle = nil
            local axeSlot = -1

            for i = 0, 8 do
                local it = NPC.GetItemByIndex(me, i)
                if it and IsAxeItem(it) then
                    axeHandle = it
                    axeSlot = i
                    break
                end
            end

            if axeHandle and axeSlot <= 5 then
                local freeBackpackSlot = -1
                for i = 6, 8 do
                    if not NPC.GetItemByIndex(me, i) then
                        freeBackpackSlot = i
                        break
                    end
                end

                if freeBackpackSlot ~= -1 then
                    Player.PrepareUnitOrders(
                        p,
                        Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM,
                        freeBackpackSlot,
                        Vector(0,0,0),
                        axeHandle,
                        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
                        me
                    )
                    print("[FLASK] Переместил топорик в ранец: слот " .. freeBackpackSlot)
                    f.move_time = os.clock()
                    f.axe_processed = true
                    return
                end
            end

            -- Топорик не найден, уже в ранце, или нет места в ранце.
            f.axe_processed = true
            f.move_time = os.clock()
            return
        end
    end

    -- ЭТАП 5: ПОСЛЕ ВСЕГО БЕЖИМ (и считаем завершенным только когда реально дошли)
    if f.was_used and not f.finished and f.axe_processed then
        if f.finish_move_ordered then
            if (hero_pos - FINISH_POS):Length2D() <= 120 then
                Player.PrepareUnitOrders(
                    p,
                    Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
                    nil,
                    Vector(0, 0, 0),
                    nil,
                    Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
                    me
                )
                print("[FLASK] Финиш достигнут. Завершаю фазу.")
                f.finished = true
                f.is_active = false
            end
            return
        end

        if os.clock() - f.move_time > 0.2 then

            -- СРАЗУ ПОСЛЕ ЭТОГО БЕЖИМ
            Player.PrepareUnitOrders(
                p, 
                Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION, 
                nil, 
                FINISH_POS, 
                nil, 
                Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, 
                me
            )
            print("[FLASK] Идем к финишу Vector(-11973, -1824, 640).")

            f.finish_move_ordered = true
        end
    end
end

return {
    OnUpdate = function()
        if GetGlobalPhase() ~= PHASE_ID then return end

        local me = Heroes.GetLocal()
        if not me or not Entity.IsAlive(me) then return end
        local p = Players.GetLocal()
        if not p then return end
        local hero_pos = Entity.GetAbsOrigin(me)
        if not hero_pos then return end

        bsa_final.HandleFlask(me, p, hero_pos)

        if bsa_final.flask_logic.finished then
            SetGlobalPhase(NEXT_PHASE_ID)
        end
    end
}