local bsa_coords_debug = {}

-- Настройки отображения
local config = {
    font = Render.LoadFont("Arial", 22, Enum.FontCreate.FONTFLAG_ANTIALIAS),
    text_color = Color(0, 255, 255, 255),  -- Голубой (для самих координат)
    label_color = Color(255, 255, 0, 255), -- Желтый (для заголовка)
    print_interval = 2.0,                  -- Частота вывода в консоль (сек)
    last_print = 0
}

function bsa_coords_debug.OnUpdate()
    local me = Heroes.GetLocal()
    if not me then return end

    local now = os.clock()
    
    -- Вывод в лог консоли каждые 2 секунды
    if now - config.last_print > config.print_interval then
        local pos = Entity.GetAbsOrigin(me)
        -- В v2.0 обращение к осям через .x, .y, .z
        Log.Write(string.format("DEB_POS: Vector(%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z))
        config.last_print = now
    end
end

function bsa_coords_debug.OnDraw()
    local me = Heroes.GetLocal()
    if not me then return end

    local pos = Entity.GetAbsOrigin(me)
    
    -- Превращаем мировые координаты в экранные (v2.0 стандарт)
    local screen_pos, is_visible = Render.WorldToScreen(pos)

    if is_visible and screen_pos then
        local coord_text = string.format("Vector(%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z)
        
        -- Отрисовка текста над головой героя (смещения через Vec2)
        -- Координаты рисуются в две строчки
        Render.Text(
            config.font, 
            20, 
            "YOUR COORDINATES:", 
            screen_pos + Vec2(0, -55), 
            config.label_color
        )
        
        Render.Text(
            config.font, 
            24, 
            coord_text, 
            screen_pos + Vec2(0, -30), 
            config.text_color
        )
    end
end

return bsa_coords_debug