const std = @import("std");
const globals = @import("globals.zig");
const data = @import("data.zig");
const display = @import("display.zig");
const vx = @import("vx.zig");

const NUMTOPS: i32 = 3;
const STRSIZE = globals.STRSIZE;

// State
var need_delay: bool = false;

// Internal: write a pre-formatted string to a top line
pub fn writeTopmsg(line: i32, text: [*:0]const u8) void {
    var l = line;
    if (l < 1 or l > NUMTOPS) l = 1;
    const row: u16 = @intCast(l - 1);

    // Write text
    var col: u16 = 0;
    var i: usize = 0;
    while (text[i] != 0) : (i += 1) {
        if (col >= vx.term_width) break;
        vx.writeCell(col, row, @intCast(text[i] & 0x7F), .{});
        col += 1;
    }
    // Clear to end of line
    while (col < vx.term_width) : (col += 1) {
        vx.clearCell(col, row);
    }
}

// Exported formatted functions

pub fn topmsg(line: i32, comptime fmt: []const u8, args: anytype) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(line, s);
}

pub fn prompt(comptime fmt: []const u8, args: anytype) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(1, s);
}

pub fn @"error"(comptime fmt: []const u8, args: anytype) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(2, s);
}

pub fn extra(comptime fmt: []const u8, args: anytype) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(3, s);
}

pub fn huh() void {
    writeTopmsg(2, "Type H for Help.");
}

pub fn info(a: [*:0]const u8, b: [*:0]const u8, c_str: [*:0]const u8) void {
    if (need_delay) display.delay();
    writeTopmsg(1, a);
    writeTopmsg(2, b);
    writeTopmsg(3, c_str);
    need_delay = true;
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

pub fn comment(comptime fmt: []const u8, args: anytype) void {
    if (need_delay) display.delay();
    writeTopmsg(1, "");
    writeTopmsg(2, "");
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(3, s);
    need_delay = true;
}

pub fn pdebug(comptime fmt: []const u8, args: anytype) void {
    if (!globals.print_debug) return;

    if (need_delay) display.delay();
    writeTopmsg(1, "");
    writeTopmsg(2, "");
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    writeTopmsg(3, s);
    need_delay = true;
}

pub fn ksend(comptime fmt: []const u8, args: anytype) void {
    var junkbuf: [STRSIZE]u8 = undefined;
    const s = std.fmt.bufPrintZ(&junkbuf, fmt, args) catch return;
    const file = std.fs.cwd().createFile("info_list.txt", .{ .truncate = false }) catch {
        @"error"("Cannot open info_list.txt", .{});
        return;
    };
    defer file.close();
    const end_pos = file.getEndPos() catch 0;
    file.seekTo(end_pos) catch return;
    file.writeAll(s) catch {};
}

// Input functions

pub fn get_str(buf: [*]u8, sizep: i32) void {
    get_strq(buf, sizep);
}

fn get_strq(buf: [*]u8, sizep: i32) void {
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

pub fn getint(message: [*:0]const u8) i32 {
    while (true) {
        writeTopmsg(1, message);
        var buf: [STRSIZE]u8 = undefined;
        get_str(&buf, STRSIZE);

        var valid = true;
        var len: usize = 0;
        while (buf[len] != 0) : (len += 1) {
            if (buf[len] < '0' or buf[len] > '9') {
                @"error"("Please enter an integer.", .{});
                valid = false;
                break;
            }
        }
        if (valid) {
            if (len > 7) {
                @"error"("Please enter a small integer.", .{});
            } else {
                return std.fmt.parseInt(i32, buf[0..len], 10) catch 0;
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

pub fn getyn(message: [*:0]const u8) bool {
    while (true) {
        writeTopmsg(1, message);
        const ch = get_chx();
        if (ch == 'Y') return true;
        if (ch == 'N') return false;
        @"error"("Please answer Y or N.", .{});
    }
}

pub fn get_range(message: [*:0]const u8, low: i32, high: i32) i32 {
    while (true) {
        const result = getint(message);
        if (result >= low and result <= high) return result;
        @"error"("Please enter an integer in the range {d}..{d}.", .{ low, high });
    }
}

// Help screen

pub fn help(text: []const [*:0]const u8, nlines: i32) void {
    const text_lines = @divTrunc(nlines + 1, 2);

    display.clear_screen();

    display.pos_str(NUMTOPS, 1, "{s}", .{text[0]});
    display.pos_str(NUMTOPS, 41, "See empire(6) for more information.", .{});

    var i: i32 = 1;
    while (i < nlines) : (i += 1) {
        if (i > text_lines) {
            display.pos_str(i - text_lines + NUMTOPS + 1, 41, "{s}", .{text[@intCast(i)]});
        } else {
            display.pos_str(i + NUMTOPS + 1, 1, "{s}", .{text[@intCast(i)]});
        }
    }

    display.pos_str(text_lines + NUMTOPS + 2, 1, "--Piece---Yours-Enemy-Moves-Hits-Cost", .{});
    display.pos_str(text_lines + NUMTOPS + 2, 41, "--Piece---Yours-Enemy-Moves-Hits-Cost", .{});

    const num_objects: i32 = globals.NUM_OBJECTS;
    i = 0;
    while (i < num_objects) : (i += 1) {
        var r: i32 = undefined;
        var col: i32 = undefined;
        if (i >= @divTrunc(num_objects + 1, 2)) {
            r = i - @divTrunc(num_objects + 1, 2);
            col = 41;
        } else {
            r = i;
            col = 1;
        }
        const idx: usize = @intCast(i);
        const sname = data.piece_attr[idx].sname;
        const nick = std.mem.sliceTo(&data.piece_attr[idx].nickname, 0);
        display.pos_str(
            r + text_lines + NUMTOPS + 3,
            col,
            "{s:<12}{c}     {c}{d:6}{d:5}{d:6}",
            .{
                nick,
                sname,
                sname | 0x20,
                data.piece_attr[idx].speed,
                data.piece_attr[idx].max_hits,
                data.piece_attr[idx].build_time,
            },
        );
    }
    vx.render();
}

// Location display

const COL_DIGITS: i32 = if (globals.MAP_WIDTH <= 100) 2 else if (globals.MAP_WIDTH <= 1000) 3 else unreachable;

pub fn loc_disp(loc: i32) i32 {
    const row = @divTrunc(loc, globals.MAP_WIDTH);
    var nrow = row;
    const col = @rem(loc, globals.MAP_WIDTH);
    std.debug.assert(loc == row * globals.MAP_WIDTH + col);
    var i: i32 = COL_DIGITS;
    while (i > 0) : (i -= 1) {
        nrow *= 10;
    }
    return nrow + col;
}
