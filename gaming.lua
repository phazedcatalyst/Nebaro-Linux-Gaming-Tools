-- Gaming hours overlay — neon Cairo rendering
-- Reads from ~/.config/conky/steam_cache.json + wow_hours.json

require 'cairo'
require 'cairo_xlib'

local C = {
    bg      = {0.04, 0.05, 0.13, 0.91},
    cyan    = {0.0,  1.0,  1.0,  1.0 },
    magenta = {1.0,  0.05, 0.88, 1.0 },
    green   = {0.14, 1.0,  0.0,  1.0 },
    blue    = {0.22, 0.52, 1.0,  1.0 },
    orange  = {1.0,  0.42, 0.0,  1.0 },
    yellow  = {1.0,  0.92, 0.0,  1.0 },
    gold    = {1.0,  0.78, 0.0,  1.0 },
    white   = {1.0,  1.0,  1.0,  0.95},
    sub     = {0.58, 0.65, 0.82, 0.80},
    bar_bg  = {0.09, 0.11, 0.21, 0.88},
}

local GAME_COLORS = {
    {C.cyan, C.magenta},
    {C.blue, C.cyan},
    {C.magenta, C.orange},
    {C.green, C.cyan},
    {C.orange, C.yellow},
}

local WOW_COLORS = {
    {C.gold, C.orange},
    {C.yellow, C.gold},
    {C.orange, C.yellow},
    {C.gold, C.cyan},
}

local function col(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4])
end

local function rrect(cr, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_arc(cr, x + r,     y + r,     r, math.pi,         3 * math.pi / 2)
    cairo_arc(cr, x + w - r, y + r,     r, 3 * math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0,               math.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2,     math.pi)
    cairo_close_path(cr)
end

local function gbar(cr, x, y, w, h, pct, c1, c2)
    pct = math.max(0, math.min(100, tonumber(pct) or 0))
    local fw = math.max(h, w * pct / 100)
    col(cr, C.bar_bg)
    rrect(cr, x, y, w, h, h / 2)
    cairo_fill(cr)
    if pct > 1 then
        local pat = cairo_pattern_create_linear(x, y, x + w, y)
        cairo_pattern_add_color_stop_rgba(pat, 0, c1[1], c1[2], c1[3], 1)
        cairo_pattern_add_color_stop_rgba(pat, 1, c2[1], c2[2], c2[3], 1)
        cairo_set_source(cr, pat)
        rrect(cr, x, y, fw, h, h / 2)
        cairo_fill(cr)
        cairo_pattern_destroy(pat)
        cairo_set_source_rgba(cr, c2[1], c2[2], c2[3], 0.10)
        rrect(cr, x, y - 1, fw, h + 2, h / 2 + 1)
        cairo_fill(cr)
    end
end

local function divline(cr, x, y, w, c1, c2)
    local pat = cairo_pattern_create_linear(x, y, x + w, y)
    cairo_pattern_add_color_stop_rgba(pat, 0,    0, 0, 0, 0)
    cairo_pattern_add_color_stop_rgba(pat, 0.08, c1[1], c1[2], c1[3], 0.9)
    cairo_pattern_add_color_stop_rgba(pat, 0.92, c2[1], c2[2], c2[3], 0.9)
    cairo_pattern_add_color_stop_rgba(pat, 1,    0, 0, 0, 0)
    cairo_set_source(cr, pat)
    cairo_set_line_width(cr, 1.3)
    cairo_move_to(cr, x, y)
    cairo_line_to(cr, x + w, y)
    cairo_stroke(cr)
    cairo_pattern_destroy(pat)
end

local function font(cr, sz, bold)
    cairo_select_font_face(cr, 'JetBrainsMono Nerd Font',
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, sz)
end

local function tw(cr, s)
    local ok, te = pcall(function()
        local e = cairo_text_extents_t:create()
        cairo_text_extents(cr, s, e)
        return e
    end)
    if ok and te and te.width then return te.width, te.x_bearing or 0 end
    return #s * 8, 0
end

local function glow(cr, x, y, s, c, radius)
    radius = radius or 1
    cairo_set_source_rgba(cr, c[1], c[2], c[3], 0.18)
    for _, o in ipairs({{-radius,0},{radius,0},{0,-radius},{0,radius}}) do
        cairo_move_to(cr, x + o[1], y + o[2])
        cairo_show_text(cr, s)
    end
    col(cr, c)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, s)
end

-- Cache: only re-run Python every 120 s
local gcache, gtime = nil, 0

local function load_gaming()
    local now = os.time()
    if gcache and (now - gtime) < 120 then return gcache end

    local fh = io.popen('python3 /home/phazed/.config/conky/read_gaming.py 2>/dev/null')
    local line = fh and fh:read('*l') or ''
    if fh then fh:close() end

    local p = {}
    for v in (line .. '|'):gmatch('([^|]*)|') do p[#p + 1] = v end

    local games = {}
    for i = 1, 5 do
        local b = 2 + (i - 1) * 3
        games[i] = {
            name  = p[b + 1] or '---',
            hours = tonumber(p[b + 2]) or 0,
            pct   = tonumber(p[b + 3]) or 0,
        }
    end

    local wow_count = tonumber(p[18]) or 0
    local wow_total = tonumber(p[19]) or 0
    local wow_chars = {}
    for i = 1, math.min(wow_count, 5) do
        local b = 19 + (i - 1) * 4
        wow_chars[i] = {
            name  = p[b + 1] or '---',
            class = p[b + 2] or '',
            hours = tonumber(p[b + 3]) or 0,
            pct   = tonumber(p[b + 4]) or 0,
        }
    end

    gcache = {
        total_hours = tonumber(p[1]) or 0,
        game_count  = tonumber(p[2]) or 0,
        games       = games,
        wow_count   = wow_count,
        wow_total   = wow_total,
        wow_chars   = wow_chars,
    }
    gtime = now
    return gcache
end

function conky_main()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr  = cairo_create(cs)
    local W   = conky_window.width
    local H   = conky_window.height
    local pad = 18
    local bw  = W - pad * 2

    local gd = load_gaming()

    -- Background
    col(cr, C.bg)
    rrect(cr, 0, 0, W, H, 14)
    cairo_fill(cr)

    -- Border: green → cyan → green
    local bp = cairo_pattern_create_linear(0, 0, W, H)
    cairo_pattern_add_color_stop_rgba(bp, 0.0, 0.14, 1.0, 0.0,  0.75)
    cairo_pattern_add_color_stop_rgba(bp, 0.5, 0.0,  1.0, 1.0,  0.55)
    cairo_pattern_add_color_stop_rgba(bp, 1.0, 0.14, 1.0, 0.0,  0.75)
    cairo_set_source(cr, bp)
    cairo_set_line_width(cr, 1.6)
    rrect(cr, 0.8, 0.8, W - 1.6, H - 1.6, 14)
    cairo_stroke(cr)
    cairo_pattern_destroy(bp)

    local y = 0
    local combined = gd.total_hours + gd.wow_total

    -- ── Total gaming banner ─────────────────────────────────────────────────
    y = y + 26
    font(cr, 8.5, false)
    local label = 'EST. TOTAL GAMING  \xc2\xb7  2014 \xe2\x80\x93 PRESENT'
    local lw, lb = tw(cr, label)
    cairo_set_source_rgba(cr, 0.45, 0.55, 0.78, 0.65)
    cairo_move_to(cr, (W - lw) / 2 - lb, y)
    cairo_show_text(cr, label)

    y = y + 50
    font(cr, 46, true)
    local ci = math.floor(combined)
    local hstr = string.format('%s h', ci >= 1000
        and string.format('%d,%03d', math.floor(ci / 1000), ci % 1000)
        or  tostring(ci))
    local hw, hb = tw(cr, hstr)
    glow(cr, (W - hw) / 2 - hb, y, hstr, C.cyan, 2)

    y = y + 18
    font(cr, 9, false)
    local sub = string.format('Steam %.0fh  \xc2\xb7  WoW %.0fh', gd.total_hours, gd.wow_total)
    local sw, sb = tw(cr, sub)
    cairo_set_source_rgba(cr, 0.45, 0.92, 1.0, 0.65)
    cairo_move_to(cr, (W - sw) / 2 - sb, y)
    cairo_show_text(cr, sub)

    y = y + 16
    divline(cr, pad, y, bw, C.cyan, C.magenta)

    -- ── Steam header
    y = y + 36
    font(cr, 11, true)
    glow(cr, pad, y, '\xef\x8a\x97  STEAM LIBRARY', C.green, 1)

    -- Subtitle
    y = y + 20
    font(cr, 9, false)
    col(cr, C.sub)
    cairo_move_to(cr, pad, y)
    cairo_show_text(cr, string.format('%d games  \xc2\xb7  %.0f total hours', gd.game_count, gd.total_hours))

    -- Divider
    y = y + 14
    divline(cr, pad, y, bw, C.green, C.cyan)

    -- Top 5 game rows
    for i, g in ipairs(gd.games) do
        local c1 = GAME_COLORS[i][1]
        local c2 = GAME_COLORS[i][2]

        -- Name line
        y = y + 22
        font(cr, 9.5, true)
        col(cr, C.white)
        cairo_move_to(cr, pad, y)
        cairo_show_text(cr, g.name)

        -- Hours (right-aligned on name line)
        local hstr = string.format('%.0fh', g.hours)
        font(cr, 9, false)
        local hw, _ = tw(cr, hstr)
        col(cr, C.sub)
        cairo_move_to(cr, W - pad - hw, y)
        cairo_show_text(cr, hstr)

        -- Bar below name
        y = y + 13
        gbar(cr, pad, y - 9, bw, 10, g.pct, c1, c2)
    end

    -- Divider before WoW
    y = y + 16
    divline(cr, pad, y, bw, C.cyan, C.gold)

    -- WoW header
    y = y + 26
    font(cr, 11, true)
    glow(cr, pad, y, '\xef\x9c\x89  WoW CHARACTERS', C.gold, 1)

    if gd.wow_count == 0 then
        -- Placeholder
        y = y + 20
        font(cr, 8.5, false)
        col(cr, C.sub)
        cairo_move_to(cr, pad, y)
        cairo_show_text(cr, 'Add /played data to wow_hours.json')
        y = y + 16
        cairo_move_to(cr, pad, y)
        cairo_show_text(cr, '~/.config/conky/wow_hours.json')
    else
        -- Total WoW hours
        y = y + 18
        font(cr, 9, false)
        col(cr, C.sub)
        cairo_move_to(cr, pad, y)
        cairo_show_text(cr, string.format('%.0f total hours across %d characters', gd.wow_total, gd.wow_count))

        -- Character rows
        for i, c in ipairs(gd.wow_chars) do
            local ci = ((i - 1) % #WOW_COLORS) + 1
            local c1 = WOW_COLORS[ci][1]
            local c2 = WOW_COLORS[ci][2]

            y = y + 22
            font(cr, 9.5, true)
            col(cr, C.white)
            cairo_move_to(cr, pad, y)
            cairo_show_text(cr, c.name)

            -- Class label
            font(cr, 8, false)
            col(cr, C.sub)
            local clw, _ = tw(cr, c.class)
            cairo_move_to(cr, W - pad - clw - 52, y)
            cairo_show_text(cr, c.class)

            -- Hours
            local hstr = string.format('%.0fh', c.hours)
            local hw, _ = tw(cr, hstr)
            col(cr, C.sub)
            cairo_move_to(cr, W - pad - hw, y)
            cairo_show_text(cr, hstr)

            y = y + 13
            gbar(cr, pad, y - 9, bw, 10, c.pct, c1, c2)
        end
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
