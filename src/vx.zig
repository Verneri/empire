/// Thin module holding global vaxis state and minimal helpers.
/// All rendering and input logic lives in the consuming files
/// (display.zig, terminal.zig, edit.zig) using vaxis APIs directly.
const std = @import("std");
const vaxis = @import("vaxis");

pub const Key = vaxis.Key;
pub const Cell = vaxis.Cell;
pub const Style = vaxis.Cell.Style;
pub const Color = vaxis.Cell.Color;

// ── global vaxis state ───────────────────────────────────────────────────
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var alloc: std.mem.Allocator = undefined;
var vx: vaxis.Vaxis = undefined;
var tty: vaxis.Tty = undefined;
var tty_buf: [4096]u8 = undefined;
var loop: vaxis.Loop(vaxis.Event) = undefined;

pub var term_height: u16 = 24;
pub var term_width: u16 = 80;

// ── static grapheme table (stable lifetime for vaxis Cell slices) ────────
pub const ascii_lut: [128][1]u8 = blk: {
    var t: [128][1]u8 = undefined;
    for (0..128) |i| t[i] = .{@intCast(i)};
    break :blk t;
};

// ── lifecycle ────────────────────────────────────────────────────────────

pub fn init() void {
    alloc = gpa.allocator();
    vx = vaxis.init(alloc, .{}) catch @panic("vaxis init failed");
    tty = vaxis.Tty.init(&tty_buf) catch @panic("tty init failed");

    loop = .{ .tty = &tty, .vaxis = &vx };
    loop.init() catch @panic("loop init failed");
    loop.start() catch @panic("loop start failed");

    vx.enterAltScreen(tty.writer()) catch @panic("alt screen failed");

    const ws = vaxis.Tty.getWinsize(tty.fd) catch vaxis.Winsize{ .rows = 24, .cols = 80, .x_pixel = 0, .y_pixel = 0 };
    vx.resize(alloc, tty.writer(), ws) catch @panic("resize failed");
    term_height = ws.rows;
    term_width = ws.cols;

    vx.screen.cursor_vis = false;

    // Drain any pending resize events from the event loop so they don't
    // wipe the screen later when getch() is called.
    // Give the event loop thread a moment to post any initial events.
    std.Thread.sleep(50 * std.time.ns_per_ms);
    drainResizeEvents();
}

pub fn deinit() void {
    vx.screen.cursor_vis = true;
    vx.render(tty.writer()) catch {};
    loop.stop();
    vx.deinit(alloc, tty.writer());
    tty.deinit();
    _ = gpa.deinit();
}

// ── dimensions ───────────────────────────────────────────────────────────

pub fn lines() c_int {
    return @intCast(term_height);
}

pub fn cols() c_int {
    return @intCast(term_width);
}

// ── cell output ──────────────────────────────────────────────────────────

pub fn writeCell(col: u16, row: u16, char: u7, style: Style) void {
    if (row >= term_height or col >= term_width) return;
    const cell: Cell = .{
        .char = .{ .grapheme = &ascii_lut[char], .width = 1 },
        .style = style,
    };
    vx.screen.writeCell(col, row, cell);
}

pub fn clearCell(col: u16, row: u16) void {
    if (row >= term_height or col >= term_width) return;
    vx.screen.writeCell(col, row, .{});
}

// ── screen ops ───────────────────────────────────────────────────────────

pub fn clear() void {
    vx.screen.clear();
}

pub fn render() void {
    vx.screen.cursor_vis = false;
    vx.render(tty.writer()) catch {};
}

pub fn fullRedraw() void {
    vx.queueRefresh();
    vx.screen.cursor_vis = false;
    vx.render(tty.writer()) catch {};
}

// ── input ────────────────────────────────────────────────────────────────

fn handleResize(ws: vaxis.Winsize) void {
    term_height = ws.rows;
    term_width = ws.cols;
    vx.resize(alloc, tty.writer(), ws) catch {};
    // Queue a full refresh so the next render repaints the whole screen,
    // since resize() reinitializes the screen buffer.
    vx.queueRefresh();
}

/// Drain any pending resize events without blocking.
fn drainResizeEvents() void {
    while (true) {
        const event = loop.tryEvent() orelse break;
        switch (event) {
            .winsize => |ws| handleResize(ws),
            else => {},
        }
    }
}

pub fn getch() u21 {
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.codepoint == 'c' and key.mods.ctrl) {
                    deinit();
                    std.c.exit(1);
                }
                // ctrl+key: ctrl+L = 12, etc.
                if (key.mods.ctrl and key.codepoint >= 'a' and key.codepoint <= 'z') {
                    return key.codepoint - 'a' + 1;
                }
                return key.codepoint;
            },
            .winsize => |ws| handleResize(ws),
            else => {},
        }
    }
}

pub fn getnstr(buf: [*c]u8, n: c_int) void {
    const max: usize = if (n < 1) 0 else @intCast(n - 1);
    var len: usize = 0;
    var cursor_x: u16 = 0;
    var cursor_y: u16 = 0;

    // Find initial cursor position from screen cursor
    cursor_y = vx.screen.cursor.row;
    cursor_x = vx.screen.cursor.col;

    vx.screen.cursor_vis = true;
    vx.render(tty.writer()) catch {};

    while (len < max) {
        const ch = getch();
        if (ch == '\r' or ch == '\n') break;
        if (ch == 127 or ch == 8) { // backspace
            if (len > 0) {
                len -= 1;
                if (cursor_x > 0) cursor_x -= 1;
                clearCell(cursor_x, cursor_y);
                vx.screen.cursor = .{ .row = cursor_y, .col = cursor_x };
                vx.render(tty.writer()) catch {};
            }
            continue;
        }
        if (ch >= 0x20 and ch < 0x7F) {
            buf[len] = @truncate(ch);
            len += 1;
            writeCell(cursor_x, cursor_y, @intCast(ch), .{});
            cursor_x +|= 1;
            vx.screen.cursor = .{ .row = cursor_y, .col = cursor_x };
            vx.render(tty.writer()) catch {};
        }
    }
    buf[len] = 0;
    vx.screen.cursor_vis = false;
}

// ── misc ─────────────────────────────────────────────────────────────────

pub fn beep() void {
    tty.writer().writeByte(0x07) catch {};
}

pub fn sleep(ms: c_int) void {
    if (ms <= 0) return;
    const ns: u64 = @as(u64, @intCast(ms)) * std.time.ns_per_ms;
    std.Thread.sleep(ns);
}
