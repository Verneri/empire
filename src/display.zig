const std = @import("std");
const globals = @import("globals.zig");
const types = @import("types.zig");
const data = @import("data.zig");
const terminal = @import("terminal.zig");
const util = @import("util.zig");
const vx = @import("vx.zig");

const c = @cImport({
    @cInclude("stdio.h");
});

const view_map_t = types.view_map_t;
const path_map_t = types.path_map_t;

const STRSIZE = globals.STRSIZE;
const MAP_WIDTH = globals.MAP_WIDTH;
const MAP_HEIGHT = globals.MAP_HEIGHT;
const ROWS_PER_SECTOR = globals.ROWS_PER_SECTOR;
const COLS_PER_SECTOR = globals.COLS_PER_SECTOR;

const NUMTOPS: c_int = 3;
const NUMSIDES: c_int = 6;
const USER = @intFromEnum(globals.Ownership.User);
const COMP = @intFromEnum(globals.Ownership.Comp);
const UNOWNED = @intFromEnum(globals.Ownership.Unowned);
const T_PATH: u8 = 1;
const INFINITY: c_int = 10000000;

const VaList = std.builtin.VaList;

// C library (for vsnprintf / snprintf)
extern fn vsnprintf(buf: [*c]u8, size: c_ulong, fmt: [*c]const u8, ap: *VaList) c_int;

// ── styles ───────────────────────────────────────────────────────────────
const style_default: vx.Style = .{ .fg = .{ .index = 7 }, .bold = true };
const style_green: vx.Style = .{ .fg = .{ .index = 2 }, .bold = true };
const style_cyan: vx.Style = .{ .fg = .{ .index = 6 }, .bold = true };
const style_red: vx.Style = .{ .fg = .{ .index = 1 }, .bold = true };
const style_white: vx.Style = .{ .fg = .{ .index = 7 }, .bold = true };

fn style_for(ch: u8) vx.Style {
    return switch (ch) {
        data.MAP_LAND => style_green,
        data.MAP_SEA => style_cyan,
        'a', 'f', 'p', 'd', 'b', 't', 'c', 's', 'z', 'X' => style_red,
        else => style_white,
    };
}

// State
var whose_map: c_int = UNOWNED;
var ref_row: c_int = 0;
var ref_col: c_int = 0;
var save_sector: c_int = 0;
var save_cursor: c_long = 0;
var change_ok: bool = true;

// ── cursor tracking for move_cursor / show_loc ───────────────────────────
// These track the logical cursor position on the map display.
var cursor_row: c_int = 0;
var cursor_col: c_int = 0;

fn disp_square_at(col: u16, row: u16, vp: *view_map_t) void {
    vx.writeCell(col, row, @intCast(vp.contents & 0x7F), style_for(vp.contents));
}

// Public API

pub fn announce(msg: [*c]const u8) void {
    if (msg == null) return;
    var i: usize = 0;
    while (msg[i] != 0) : (i += 1) {
        const col: u16 = @as(u16, @intCast(cursor_col)) +| @as(u16, @intCast(i));
        if (col >= vx.term_width) break;
        vx.writeCell(col, @intCast(cursor_row), @intCast(msg[i] & 0x7F), style_default);
    }
}

pub fn direction(ch: u21) c_int {
    return switch (ch) {
        'w', 'W', vx.Key.up => 0,
        'e', 'E', vx.Key.page_up => 1,
        'd', 'D', vx.Key.right => 2,
        'c', 'C', vx.Key.page_down => 3,
        'x', 'X', vx.Key.down => 4,
        'z', 'Z', vx.Key.end => 5,
        'a', 'A', vx.Key.left => 6,
        'q', 'Q', vx.Key.home => 7,
        else => -1,
    };
}

pub fn kill_display() void {
    whose_map = UNOWNED;
}

pub fn sector_change() void {
    change_ok = true;
}

pub fn cur_sector() c_int {
    if (whose_map != USER) return -1;
    return save_sector;
}

pub fn cur_cursor() c_long {
    if (whose_map != USER) return -1;
    return save_cursor;
}

fn on_screen(loc: c_long) bool {
    const new_r = util.loc_row(loc);
    const new_c = util.loc_col(loc);

    if (new_r < ref_row or
        new_r - ref_row > globals.lines - NUMTOPS - 1 or
        new_c < ref_col or
        new_c - ref_col > globals.cols - NUMSIDES)
        return false;

    return true;
}

fn show_loc(vmap: [*c]view_map_t, loc: c_long) void {
    const r: c_int = @intCast(util.loc_row(loc));
    const col: c_int = @intCast(util.loc_col(loc));
    const scr_row = r - ref_row + NUMTOPS;
    const scr_col = col - ref_col;
    const uloc: usize = @intCast(loc);
    disp_square_at(@intCast(scr_col), @intCast(scr_row), @ptrCast(&vmap[uloc]));
    save_cursor = loc;
    cursor_row = scr_row;
    cursor_col = scr_col;
}

pub fn display_loc(whose: c_int, vmap: [*c]view_map_t, loc: c_long) void {
    if (change_ok or whose != whose_map or !on_screen(loc))
        print_sector(whose, vmap, util.loc_sector(loc));

    show_loc(vmap, loc);
}

pub fn display_locx(whose: c_int, vmap: [*c]view_map_t, loc: c_long) void {
    if (whose == whose_map and on_screen(loc)) show_loc(vmap, loc);
}

fn display_screen(vmap: [*c]view_map_t) void {
    const display_rows = globals.lines - NUMTOPS - 1;
    const display_cols = globals.cols - NUMSIDES;

    var r = ref_row;
    while (r < ref_row + display_rows and r < MAP_HEIGHT) : (r += 1) {
        var col = ref_col;
        while (col < ref_col + display_cols and col < MAP_WIDTH) : (col += 1) {
            const t = util.row_col_loc(r, col);
            const scr_row: u16 = @intCast(r - ref_row + NUMTOPS);
            const scr_col: u16 = @intCast(col - ref_col);
            disp_square_at(scr_col, scr_row, @ptrCast(&vmap[@intCast(t)]));
        }
    }
}

pub fn print_sector(whose: c_int, vmap: [*c]view_map_t, sector: c_int) void {
    save_sector = sector;
    change_ok = false;

    const display_rows = globals.lines - NUMTOPS - 1;
    const display_cols = globals.cols - NUMSIDES;

    const first_row = util.sector_row(sector) * ROWS_PER_SECTOR;
    const first_col = util.sector_col(sector) * COLS_PER_SECTOR;
    const last_row = first_row + ROWS_PER_SECTOR - 1;
    const last_col = first_col + COLS_PER_SECTOR - 1;

    if (!(whose == whose_map and
        ref_row <= first_row and
        ref_col <= first_col and
        ref_row + display_rows - 1 >= last_row and
        ref_col + display_cols - 1 >= last_col))
        vx.clear();

    ref_row = first_row - @divTrunc(display_rows - ROWS_PER_SECTOR, 2);
    ref_col = first_col - @divTrunc(display_cols - COLS_PER_SECTOR, 2);

    if (ref_row + display_rows - 1 > MAP_HEIGHT - 1)
        ref_row = MAP_HEIGHT - 1 - (display_rows - 1);
    if (ref_row < 0) ref_row = 0;

    if (ref_col + display_cols - 1 > MAP_WIDTH - 1)
        ref_col = MAP_WIDTH - 1 - (display_cols - 1);
    if (ref_col < 0) ref_col = 0;

    whose_map = whose;
    display_screen(vmap);

    // print x-coordinates along bottom of screen
    var col = ref_col;
    while (col < ref_col + display_cols and col < MAP_WIDTH) : (col += 1) {
        if (@rem(col, 10) == 0) {
            pos_str(globals.lines - 1, col - ref_col, "%d", col);
        }
    }

    // print y-coordinates along right of screen
    var r = ref_row;
    while (r < ref_row + display_rows and r < MAP_HEIGHT) : (r += 1) {
        if (@rem(r, 2) == 0)
            pos_str(r - ref_row + NUMTOPS, globals.cols - NUMSIDES + 1, "%2d", r)
        else
            pos_str(r - ref_row + NUMTOPS, globals.cols - NUMSIDES + 1, "  ");
    }

    // print round number vertically
    var jnkbuf: [STRSIZE]u8 = undefined;
    _ = c.snprintf(&jnkbuf, STRSIZE, "Sector %d Round %ld", sector, globals.date);
    r = 0;
    while (jnkbuf[@intCast(r)] != 0) : (r += 1) {
        if (r + NUMTOPS >= MAP_HEIGHT) break;
        const scr_row: u16 = @intCast(r + NUMTOPS);
        const scr_col: u16 = @intCast(globals.cols - NUMSIDES + 4);
        vx.writeCell(scr_col, scr_row, @intCast(jnkbuf[@intCast(r)]), style_default);
    }
}

pub fn move_cursor(cursor: [*c]c_long, offset: c_int) bool {
    const t = cursor.* + offset;
    if (!globals.map[@intCast(t)].on_board) return false;
    if (!on_screen(t)) return false;

    cursor.* = t;
    save_cursor = cursor.*;

    const r: c_int = @intCast(util.loc_row(save_cursor));
    const col: c_int = @intCast(util.loc_col(save_cursor));
    cursor_row = r - ref_row + NUMTOPS;
    cursor_col = col - ref_col;

    return true;
}

pub var zoom_list: [24]u8 = "XO*tcbsdpfaTCBSDPFAzZ+. ".*;

fn zoom_rank(ch: u8) usize {
    for (0..zoom_list.len) |i| {
        if (zoom_list[i] == ch) return i;
    }
    return zoom_list.len;
}

fn print_zoom_cell(vmap: [*c]view_map_t, row: c_int, col: c_int, row_inc: c_int, col_inc: c_int) void {
    var cell: u8 = ' ';
    var r = row;
    while (r < row + row_inc) : (r += 1) {
        var cc = col;
        while (cc < col + col_inc) : (cc += 1) {
            const contents = vmap[@intCast(util.row_col_loc(r, cc))].contents;
            if (zoom_rank(contents) < zoom_rank(cell))
                cell = contents;
        }
    }
    const scr_row: u16 = @intCast(@divTrunc(row, row_inc) + NUMTOPS);
    const scr_col: u16 = @intCast(@divTrunc(col, col_inc));
    vx.writeCell(scr_col, scr_row, @intCast(cell), style_for(cell));
}

pub fn print_zoom(vmap: [*c]view_map_t) void {
    kill_display();

    const row_inc = @divTrunc(MAP_HEIGHT + globals.lines - NUMTOPS - 1, globals.lines - NUMTOPS);
    const col_inc = @divTrunc(MAP_WIDTH + globals.cols - 1, globals.cols - 1);

    var r: c_int = 0;
    while (r < MAP_HEIGHT) : (r += row_inc) {
        var col: c_int = 0;
        while (col < MAP_WIDTH) : (col += col_inc) {
            print_zoom_cell(vmap, r, col, row_inc, col_inc);
        }
    }

    pos_str(0, 0, "Round #%d", globals.date);
    vx.render();
}

pub fn print_xzoom(vmap: [*c]view_map_t) void {
    print_zoom(vmap);
}

fn print_pzoom_cell(pmap: [*c]path_map_t, vmap: [*c]view_map_t, row: c_int, col: c_int, row_inc: c_int, col_inc: c_int) void {
    var sum: c_int = 0;
    var d_count: c_int = 0;

    var r = row;
    while (r < row + row_inc) : (r += 1) {
        var cc = col;
        while (cc < col + col_inc) : (cc += 1) {
            sum += pmap[@intCast(util.row_col_loc(r, cc))].cost;
            d_count += 1;
        }
    }
    sum = @divTrunc(sum, d_count);

    var cell: u8 = undefined;
    if (pmap[@intCast(util.row_col_loc(row, col))].terrain == T_PATH)
        cell = '-'
    else if (sum < 0)
        cell = '!'
    else if (sum == @divTrunc(INFINITY, 2))
        cell = 'P'
    else if (sum == INFINITY)
        cell = ' '
    else if (sum > @divTrunc(INFINITY, 2))
        cell = 'U'
    else {
        const s: u8 = @intCast(@rem(sum, 36));
        if (s < 10)
            cell = s + '0'
        else
            cell = s - 10 + 'a';
    }

    if (cell == ' ')
        print_zoom_cell(vmap, row, col, row_inc, col_inc)
    else {
        const scr_row: u16 = @intCast(@divTrunc(row, row_inc) + NUMTOPS);
        const scr_col: u16 = @intCast(@divTrunc(col, col_inc));
        vx.writeCell(scr_col, scr_row, @intCast(cell), style_default);
    }
}

pub fn print_pzoom(s: [*c]const u8, pmap: [*c]path_map_t, vmap: [*c]view_map_t) void {
    kill_display();

    const row_inc = @divTrunc(MAP_HEIGHT + globals.lines - NUMTOPS - 1, globals.lines - NUMTOPS);
    const col_inc = @divTrunc(MAP_WIDTH + globals.cols - 1, globals.cols - 1);

    var r: c_int = 0;
    while (r < MAP_HEIGHT) : (r += row_inc) {
        var col: c_int = 0;
        while (col < MAP_WIDTH) : (col += col_inc) {
            print_pzoom_cell(pmap, vmap, r, col, row_inc, col_inc);
        }
    }

    terminal.prompt(s);
    _ = terminal.get_chx();
    vx.render();
}

pub fn display_score() void {
    pos_str(1, globals.cols - 12, " User  Comp");
    pos_str(2, globals.cols - 12, "%5d %5d", globals.user_score, globals.comp_score);
}

pub fn clreol(linep: c_int, colp: c_int) void {
    const row: u16 = @intCast(linep);
    var x: u16 = @intCast(colp);
    while (x < vx.term_width) : (x += 1) {
        vx.clearCell(x, row);
    }
}

pub fn ttinit() void {
    vx.init();
    globals.lines = vx.lines();
    globals.cols = vx.cols();
    if (globals.lines > MAP_HEIGHT + NUMTOPS + 1) globals.lines = MAP_HEIGHT + NUMTOPS + 1;
    if (globals.cols > MAP_WIDTH + NUMSIDES) globals.cols = MAP_WIDTH + NUMSIDES;
}

pub fn clear_screen() void {
    vx.clear();
    vx.fullRedraw();
    kill_display();
}

pub fn complain() void {
    vx.beep();
}

pub fn redisplay() void {
    vx.render();
}

pub fn redraw() void {
    vx.fullRedraw();
}

pub fn delay() void {
    var t = globals.delay_time;
    const i: c_int = 500;
    vx.render();
    if (t > i) {
        cursor_row = vx.lines() - 1;
        cursor_col = 0;
    }
    while (t > 0) : (t -= i) {
        vx.sleep(if (t > i) i else t);
        if (t > i) {
            vx.writeCell(@intCast(cursor_col), @intCast(cursor_row), '*', style_default);
            cursor_col += 1;
            vx.render();
        }
    }
}

pub fn close_disp() void {
    // Clear bottom line
    const row: u16 = @intCast(vx.lines() - 1);
    var x: u16 = 0;
    while (x < vx.term_width) : (x += 1) {
        vx.clearCell(x, row);
    }
    vx.render();
    vx.deinit();
}

pub fn pos_str(row: c_int, col: c_int, str: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    var junkbuf: [STRSIZE]u8 = undefined;
    _ = vsnprintf(&junkbuf, STRSIZE, str, &ap);

    // Write the formatted string at (col, row)
    var i: usize = 0;
    while (junkbuf[i] != 0) : (i += 1) {
        const scr_col: u16 = @as(u16, @intCast(col)) +| @as(u16, @intCast(i));
        if (scr_col >= vx.term_width) break;
        vx.writeCell(scr_col, @intCast(row), @intCast(junkbuf[i] & 0x7F), style_default);
    }
    // Update cursor to end of string for announce() compatibility
    cursor_row = row;
    cursor_col = col + @as(c_int, @intCast(i));
}

pub fn print_movie_cell(mbuf: [*c]u8, row: c_int, col: c_int, row_inc: c_int, col_inc: c_int) void {
    var cell: u8 = ' ';
    var r = row;
    while (r < row + row_inc) : (r += 1) {
        var cc = col;
        while (cc < col + col_inc) : (cc += 1) {
            const contents = mbuf[@intCast(util.row_col_loc(r, cc))];
            if (zoom_rank(contents) < zoom_rank(cell))
                cell = contents;
        }
    }
    const scr_row: u16 = @intCast(@divTrunc(row, row_inc) + NUMTOPS);
    const scr_col: u16 = @intCast(@divTrunc(col, col_inc));
    vx.writeCell(scr_col, scr_row, @intCast(cell), style_for(cell));
}

// Inline wrappers for convenience

pub inline fn print_sector_u(sector: c_int) void {
    print_sector(USER, &globals.user_map, sector);
}

pub inline fn print_sector_c(sector: c_int) void {
    print_sector(COMP, &globals.comp_map, sector);
}

pub inline fn display_loc_u(loc: c_long) void {
    display_loc(USER, &globals.user_map, loc);
}

pub inline fn display_loc_c(loc: c_long) void {
    display_loc(COMP, &globals.comp_map, loc);
}

pub fn blink_unit(loc: c_long, reverse: bool) void {
    if (!on_screen(loc)) return;
    const r: c_int = @intCast(util.loc_row(loc));
    const col: c_int = @intCast(util.loc_col(loc));
    const scr_row: u16 = @intCast(r - ref_row + NUMTOPS);
    const scr_col: u16 = @intCast(col - ref_col);
    const uloc: usize = @intCast(loc);
    const ch = globals.user_map[uloc].contents;
    var style = style_for(ch);
    if (reverse) style.reverse = true;
    vx.writeCell(scr_col, scr_row, @intCast(ch & 0x7F), style);
}
