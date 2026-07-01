-- Neon desktop overlay — full Cairo rendering
-- RTX 3090 + i7-12700K | 3440x1440 OLED

require 'cairo'
require 'cairo_xlib'

-- Neon palette (r, g, b, a)
local C = {
    bg      = {0.04, 0.05, 0.13, 0.91},
    cyan    = {0.0,  1.0,  1.0,  1.0 },
    magenta = {1.0,  0.05, 0.88, 1.0 },
    green   = {0.14, 1.0,  0.0,  1.0 },
    blue    = {0.22, 0.52, 1.0,  1.0 },
    orange  = {1.0,  0.42, 0.0,  1.0 },
    white   = {1.0,  1.0,  1.0,  0.95},
    sub     = {0.58, 0.65, 0.82, 0.80},
    bar_bg  = {0.09, 0.11, 0.21, 0.88},
}

local function col(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or c[4])
end

local function rrect(cr, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_arc(cr, x + r,     y + r,     r, math.pi,       3 * math.pi / 2)
    cairo_arc(cr, x + w - r, y + r,     r, 3 * math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0,              math.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2,    math.pi)
    cairo_close_path(cr)
end

-- Gradient bar with outer glow
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
        -- subtle glow ring
        cairo_set_source_rgba(cr, c2[1], c2[2], c2[3], 0.10)
        rrect(cr, x, y - 1, fw, h + 2, h / 2 + 1)
        cairo_fill(cr)
    end
end

-- Gradient divider line (fades at edges)
local function divline(cr, x, y, w, c1, c2)
    local pat = cairo_pattern_create_linear(x, y, x + w, y)
    cairo_pattern_add_color_stop_rgba(pat, 0,   0, 0, 0, 0)
    cairo_pattern_add_color_stop_rgba(pat, 0.08, c1[1], c1[2], c1[3], 0.9)
    cairo_pattern_add_color_stop_rgba(pat, 0.92, c2[1], c2[2], c2[3], 0.9)
    cairo_pattern_add_color_stop_rgba(pat, 1,   0, 0, 0, 0)
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

-- Text width via extents (with safe fallback)
local function tw(cr, s)
    local ok, te = pcall(function()
        local e = cairo_text_extents_t:create()
        cairo_text_extents(cr, s, e)
        return e
    end)
    if ok and te and te.width then return te.width, te.x_bearing or 0 end
    return #s * 8, 0  -- rough fallback
end

-- Subtle neon accent: thin halo at radius px, then sharp text on top
local function glow(cr, x, y, s, c, radius)
    radius = radius or 1
    cairo_set_source_rgba(cr, c[1], c[2], c[3], 0.18)
    for _, o in ipairs({ {-radius,0},{radius,0},{0,-radius},{0,radius} }) do
        cairo_move_to(cr, x + o[1], y + o[2])
        cairo_show_text(cr, s)
    end
    col(cr, c)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, s)
end

local function cv(s) return conky_parse(s) or '' end
local function cn(s) return tonumber(cv(s)) or 0 end

function conky_main()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr  = cairo_create(cs)
    local W   = conky_window.width
    local H   = conky_window.height
    local pad = 18
    local lx  = pad           -- left label x
    local bx  = pad + 54      -- bar / value x
    local bw  = W - bx - pad  -- bar width

    -- ── One nvidia-smi call for all GPU stats ─────────────────────────────
    local raw = cv('${exec nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null}')
    local g = {}
    for v in (raw .. ','):gmatch('([^,]*),') do
        g[#g + 1] = v:match('^%s*(.-)%s*$')
    end
    local gpu_util  = tonumber(g[1]) or 0
    local gpu_mempct= tonumber(g[2]) or 0
    local gpu_mem   = (g[3] or '?') .. 'M / 24G'
    local gpu_temp  = (g[4] or '?') .. '°C'
    local gpu_pow   = string.format('%.0fW', tonumber(g[5]) or 0)

    local cpu_pct   = cn('${cpu cpu0}')
    local cpu_temp  = cv('${exec sensors coretemp-isa-0000 2>/dev/null | grep "Package id 0" | awk \'{print $4}\' | tr -d \'+°C\'}')
    local cpu_freq  = cv('${freq_g}')
    local mem_pct   = cn('${memperc}')
    local mem_used  = cv('${mem}')
    local mem_max   = cv('${memmax}')
    local net_up    = cv('${upspeed enp2s0}')
    local net_dn    = cv('${downspeed enp2s0}')
    local uptime_s  = cv('${uptime_short}')
    local load1     = cv('${loadavg 1}')
    local clock     = cv('${time %H:%M:%S}')
    local datestr   = cv('${time %A  ·  %d %B %Y}')

    -- ── Background panel ────────────────────────────────────────────────────
    col(cr, C.bg)
    rrect(cr, 0, 0, W, H, 14)
    cairo_fill(cr)

    -- Neon border: cyan→magenta→cyan diagonal gradient
    local bp = cairo_pattern_create_linear(0, 0, W, H)
    cairo_pattern_add_color_stop_rgba(bp, 0.0, 0.0, 1.0, 1.0, 0.75)
    cairo_pattern_add_color_stop_rgba(bp, 0.4, 1.0, 0.0, 0.9, 0.55)
    cairo_pattern_add_color_stop_rgba(bp, 1.0, 0.0, 1.0, 1.0, 0.75)
    cairo_set_source(cr, bp)
    cairo_set_line_width(cr, 1.6)
    rrect(cr, 0.8, 0.8, W - 1.6, H - 1.6, 14)
    cairo_stroke(cr)
    cairo_pattern_destroy(bp)

    local y = 0

    -- ── Clock ───────────────────────────────────────────────────────────────
    y = y + 66
    font(cr, 54, true)
    local cw, cb = tw(cr, clock)
    glow(cr, (W - cw) / 2 - cb, y, clock, C.cyan, 2)

    y = y + 22
    font(cr, 10, false)
    local dw, db = tw(cr, datestr)
    cairo_set_source_rgba(cr, 0.45, 0.92, 1.0, 0.78)
    cairo_move_to(cr, (W - dw) / 2 - db, y)
    cairo_show_text(cr, datestr)

    y = y + 20
    divline(cr, pad, y, W - pad * 2, C.cyan, C.magenta)

    -- ── GPU ─────────────────────────────────────────────────────────────────
    y = y + 26
    font(cr, 11, true)
    glow(cr, lx, y, '󰢮  GPU  —  RTX 3090', C.magenta, 1)

    y = y + 21
    font(cr, 9, false)
    col(cr, C.sub); cairo_move_to(cr, lx, y); cairo_show_text(cr, 'Usage')
    gbar(cr, bx, y - 11, bw, 13, gpu_util, C.cyan, C.magenta)
    col(cr, C.white)
    cairo_move_to(cr, W - pad - 34, y)
    cairo_show_text(cr, string.format('%3d%%', gpu_util))

    y = y + 21
    col(cr, C.sub); cairo_move_to(cr, lx, y); cairo_show_text(cr, 'VRAM')
    gbar(cr, bx, y - 11, bw, 13, gpu_mempct, C.blue, C.magenta)
    col(cr, C.white)
    cairo_move_to(cr, W - pad - 82, y)
    cairo_show_text(cr, gpu_mem)

    y = y + 19
    col(cr, C.sub)
    cairo_move_to(cr, lx, y);       cairo_show_text(cr, 'Temp  ' .. gpu_temp)
    cairo_move_to(cr, lx + 130, y); cairo_show_text(cr, 'Power  ' .. gpu_pow)

    y = y + 16
    divline(cr, pad, y, W - pad * 2, C.magenta, C.cyan)

    -- ── CPU ─────────────────────────────────────────────────────────────────
    y = y + 26
    font(cr, 11, true)
    glow(cr, lx, y, '  CPU  —  i7-12700K', C.cyan, 1)

    y = y + 21
    font(cr, 9, false)
    col(cr, C.sub); cairo_move_to(cr, lx, y); cairo_show_text(cr, 'Usage')
    gbar(cr, bx, y - 11, bw, 13, cpu_pct, C.cyan, C.green)
    col(cr, C.white)
    cairo_move_to(cr, W - pad - 34, y)
    cairo_show_text(cr, string.format('%3d%%', cpu_pct))

    y = y + 19
    col(cr, C.sub)
    cairo_move_to(cr, lx, y);       cairo_show_text(cr, 'Temp  ' .. cpu_temp .. '°C')
    cairo_move_to(cr, lx + 130, y); cairo_show_text(cr, 'Freq  ' .. cpu_freq .. ' GHz')

    y = y + 16
    divline(cr, pad, y, W - pad * 2, C.green, C.cyan)

    -- ── Memory ──────────────────────────────────────────────────────────────
    y = y + 26
    font(cr, 11, true)
    glow(cr, lx, y, '󰍛  MEMORY', C.green, 1)

    y = y + 21
    font(cr, 9, false)
    col(cr, C.sub); cairo_move_to(cr, lx, y); cairo_show_text(cr, 'Used')
    gbar(cr, bx, y - 11, bw, 13, mem_pct, C.green, C.cyan)
    col(cr, C.white)
    cairo_move_to(cr, W - pad - 82, y)
    cairo_show_text(cr, mem_used .. ' / ' .. mem_max)

    y = y + 16
    divline(cr, pad, y, W - pad * 2, C.cyan, C.blue)

    -- ── Network ─────────────────────────────────────────────────────────────
    y = y + 26
    font(cr, 11, true)
    glow(cr, lx, y, '󰛳  NETWORK  —  enp2s0', C.blue, 1)

    y = y + 21
    font(cr, 9, false)
    col(cr, C.sub)
    cairo_move_to(cr, lx, y);        cairo_show_text(cr, '↑ Up')
    col(cr, C.white)
    cairo_move_to(cr, lx + 48, y);   cairo_show_text(cr, net_up)
    col(cr, C.sub)
    cairo_move_to(cr, lx + 158, y);  cairo_show_text(cr, '↓ Down')
    col(cr, C.white)
    cairo_move_to(cr, lx + 212, y);  cairo_show_text(cr, net_dn)

    y = y + 18
    divline(cr, pad, y, W - pad * 2, C.blue, C.magenta)

    -- ── Footer ──────────────────────────────────────────────────────────────
    y = y + 19
    font(cr, 8.5, false)
    cairo_set_source_rgba(cr, 0.32, 0.38, 0.56, 0.70)
    cairo_move_to(cr, lx, y)
    cairo_show_text(cr, 'uptime  ' .. uptime_s .. '   ·   load  ' .. load1)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
