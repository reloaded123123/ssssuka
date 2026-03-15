
local script = {}


local settings = {
    upgrade_interval = 2.0,    
    ability_slot_w = 1,        
    ability_slot_e = 2,        
    ability_slot_r = 5         
}


local state = {
    myHero = nil,
    myPlayer = nil,
    ability_w = nil,
    ability_e = nil,
    ability_r = nil,
    talent_targets = {},
    lastUpgradeTime = 0,
    initialized = false
}


function script.OnUpdate()
    
    if not state.initialized then
        state.myHero = Heroes.GetLocal()
        state.myPlayer = Players.GetLocal()
        if not (state.myHero and state.myPlayer) then
            return
        end

        state.ability_w = NPC.GetAbilityByIndex(state.myHero, settings.ability_slot_w)
        state.ability_e = NPC.GetAbilityByIndex(state.myHero, settings.ability_slot_e)
        state.ability_r = NPC.GetAbilityByIndex(state.myHero, settings.ability_slot_r)
        
        
        local all_talents = {}
        for i = 0, 31 do
            local ab = NPC.GetAbilityByIndex(state.myHero, i)
            if ab then
                local name = Ability.GetName(ab)
                if name and string.find(name, "special_bonus") then
                    table.insert(all_talents, ab)
                end
            end
        end

        
        if #all_talents >= 8 then
            local isMedusa = NPC.GetUnitName(state.myHero) == "npc_dota_hero_medusa"

            -- Порядок по тиру 10/15/20/25:
            -- Medusa: ПРАВЫЙ, ЛЕВЫЙ, ПРАВЫЙ, ЛЕВЫЙ -> 2,3,6,7
            -- Остальные: ПРАВЫЙ, ЛЕВЫЙ, ПРАВЫЙ, ПРАВЫЙ -> 2,3,6,8
            if isMedusa then
                state.talent_targets = {
                    all_talents[2],
                    all_talents[3],
                    all_talents[6],
                    all_talents[7]
                }
            else
                state.talent_targets = {
                    all_talents[2],
                    all_talents[3],
                    all_talents[6],
                    all_talents[8]
                }
            end
        end

        state.initialized = true
        return
    end

    
    local currentTime = GameRules.GetGameTime()
    if currentTime - state.lastUpgradeTime < settings.upgrade_interval then
        return
    end
    state.lastUpgradeTime = currentTime

    

    
    for _, talent in ipairs(state.talent_targets) do
        if talent and Ability.GetLevel(talent) == 0 then
            tryUpgradeAbility(talent)
        end
    end

    
    tryUpgradeAbility(state.ability_r)

    
    tryUpgradeAbility(state.ability_w)

    
    tryUpgradeAbility(state.ability_e)
end


function tryUpgradeAbility(ability)
    if not ability then return end
    
    
    if Ability.GetLevel(ability) >= Ability.GetMaxLevel(ability) then return end

    local success, _ = pcall(function()
        Player.PrepareUnitOrders(
            state.myPlayer,
            Enum.UnitOrder.DOTA_UNIT_ORDER_TRAIN_ABILITY,
            nil,
            Vector(0, 0, 0),
            ability,
            Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
            state.myHero,
            false, false, false, false,
            "autoskill",
            false
        )
    end)
end

return script