const std = @import("std");
const globals = @import("globals.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const vx = @import("vx.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

const NUMTOPS: c_int = 3;
const STRSIZE = globals.STRSIZE;
const VaList = std.builtin.VaList;

// C library
extern fn vsnprintf(buf: [*c]u8, size: c_ulong, fmt: [*c]const u8, ap: *VaList) c_int;

// State
var need_delay: bool = false;

// Internal: write a pre-formatted string to a top line
fn writeTopmsg(line: c_int, text: [*c]const u8) void {
    var l = line;
    if (l < 1 or l > NUMTOPS) l = 1;
    const row: u16 = @intCast(l - 1);

    // Write text
    var col: u16 = 0;
    if (text != null) {
        var i: usize = 0;
        while (text[i] != 0) : (i += 1) {
            if (col >= vx.term_width) break;
            vx.writeCell(col, row, @intCast(text[i] & 0x7F), .{});
            col += 1;
        }
    }
    // Clear to end of line
    while (col < vx.term_width) : (col += 1) {
        vx.clearCell(col, row);
    }
}

fn vtopmsg(line: c_int, fmt: [*c]const u8, ap: *VaList) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    _ = vsnprintf(&junkbuf, STRSIZE, fmt, ap);
    writeTopmsg(line, &junkbuf);
}

// Exported variadic functions

pub fn topmsg(line: c_int, fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vtopmsg(line, fmt, &ap);
}

pub fn prompt(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vtopmsg(1, fmt, &ap);
}

pub fn @"error"(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vtopmsg(2, fmt, &ap);
}

pub fn extra(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    vtopmsg(3, fmt, &ap);
}

pub fn huh() void {
    writeTopmsg(2, "Type H for Help.");
}

pub fn info(a: [*c]const u8, b: [*c]const u8, c_str: [*c]const u8) void {
    if (need_delay) display.delay();
    writeTopmsg(1, a);
    writeTopmsg(2, b);
    writeTopmsg(3, c_str);
    need_delay = (a != null or b != null or c_str != null);
}

pub fn set_need_delay() void {
    need_delay = true;
}

pub fn clear_need_delay() void {
    need_delay = false;
}

pub fn topini() void {
    info("", "", "");
}

pub fn comment(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    if (need_delay) display.delay();
    writeTopmsg(1, "");
    writeTopmsg(2, "");
    vtopmsg(3, fmt, &ap);
    need_delay = (fmt != null);
}

pub fn pdebug(fmt: [*c]const u8, ...) callconv(.c) void {
    if (!globals.print_debug) return;

    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    if (need_delay) display.delay();
    writeTopmsg(1, "");
    writeTopmsg(2, "");
    vtopmsg(3, fmt, &ap);
    need_delay = (fmt != null);
}

pub fn ksend(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    var junkbuf: [STRSIZE]u8 = undefined;
    _ = vsnprintf(&junkbuf, STRSIZE, fmt, &ap);
    const stream = c.fopen("info_list.txt", "a") orelse {
        @"error"("Cannot open info_list.txt");
        return;
    };
    _ = c.fputs(&junkbuf, stream);
    _ = c.fclose(stream);
}

// Input functions

pub fn get_str(buf: [*c]u8, sizep: c_int) void {
    get_strq(buf, sizep);
}

fn get_strq(buf: [*c]u8, sizep: c_int) void {
    vx.render();
    vx.getnstr(buf, sizep);
    need_delay = false;
    info("", "", "");
}

pub fn get_chx() u8 {
    const ch = get_cq();
    if (ch >= 'a' and ch <= 'z') {
        return ch - 'a' + 'A';
    }
    return ch;
}

pub fn getint(message: [*c]const u8) c_int {
    while (true) {
        prompt(message);
        var buf: [STRSIZE]u8 = undefined;
        get_str(&buf, STRSIZE);

        var valid = true;
        var len: usize = 0;
        while (buf[len] != 0) : (len += 1) {
            if (buf[len] < '0' or buf[len] > '9') {
                @"error"("Please enter an integer.");
                valid = false;
                break;
            }
        }
        if (valid) {
            if (len > 7) {
                @"error"("Please enter a small integer.");
            } else {
                return c.atoi(&buf);
            }
        }
    }
}

fn get_cq() u8 {
    vx.render();
    const ch: u21 = vx.getch();
    topini();
    return @truncate(ch);
}

pub fn getyn(message: [*c]const u8) bool {
    while (true) {
        prompt(message);
        const ch = get_chx();
        if (ch == 'Y') return true;
        if (ch == 'N') return false;
        @"error"("Please answer Y or N.");
    }
}

pub fn get_range(message: [*c]const u8, low: c_int, high: c_int) c_int {
    while (true) {
        const result = getint(message);
        if (result >= low and result <= high) return result;
        @"error"("Please enter an integer in the range %d..%d.", low, high);
    }
}

// Help screen

pub fn help(text: [*c][*c]const u8, nlines: c_int) void {
    const text_lines = @divTrunc(nlines + 1, 2);

    display.clear_screen();

    display.pos_str(NUMTOPS, 1, text[0]);
    display.pos_str(NUMTOPS, 41, "See empire(6) for more information.");

    var i: c_int = 1;
    while (i < nlines) : (i += 1) {
        if (i > text_lines) {
            display.pos_str(i - text_lines + NUMTOPS + 1, 41, text[@intCast(i)]);
        } else {
            display.pos_str(i + NUMTOPS + 1, 1, text[@intCast(i)]);
        }
    }

    display.pos_str(text_lines + NUMTOPS + 2, 1, "--Piece---Yours-Enemy-Moves-Hits-Cost");
    display.pos_str(text_lines + NUMTOPS + 2, 41, "--Piece---Yours-Enemy-Moves-Hits-Cost");

    const num_objects: c_int = globals.NUM_OBJECTS;
    i = 0;
    while (i < num_objects) : (i += 1) {
        var r: c_int = undefined;
        var col: c_int = undefined;
        if (i >= @divTrunc(num_objects + 1, 2)) {
            r = i - @divTrunc(num_objects + 1, 2);
            col = 41;
        } else {
            r = i;
            col = 1;
        }
        const idx: usize = @intCast(i);
        const sname = data.piece_attr[idx].sname;
        display.pos_str(
            r + text_lines + NUMTOPS + 3,
            col,
            "%-12s%c     %c%6d%5d%6d",
            @as([*c]const u8, &data.piece_attr[idx].nickname),
            @as(c_int, sname),
            @as(c_int, sname | 0x20),
            @as(c_int, data.piece_attr[idx].speed),
            @as(c_int, data.piece_attr[idx].max_hits),
            @as(c_int, data.piece_attr[idx].build_time),
        );
    }
    vx.render();
}

// Location display

const COL_DIGITS: c_int = if (globals.MAP_WIDTH <= 100) 2 else if (globals.MAP_WIDTH <= 1000) 3 else unreachable;

pub fn loc_disp(loc: c_int) c_int {
    const row = @divTrunc(loc, globals.MAP_WIDTH);
    var nrow = row;
    const col = @rem(loc, globals.MAP_WIDTH);
    std.debug.assert(loc == row * globals.MAP_WIDTH + col);
    var i: c_int = COL_DIGITS;
    while (i > 0) : (i -= 1) {
        nrow *= 10;
    }
    // Position cursor at bottom-left
    // (legacy: the old code used curses.move(lines-1, 0) here)
    return nrow + col;
}

// Zig-friendly wrappers

pub fn error_msg(fmt: [*c]const u8) void {
    @"error"(fmt);
}

pub fn fmt_error(fmt: [*c]const u8, args: anytype) void {
    @call(.auto, @"error", .{fmt} ++ args);
}
