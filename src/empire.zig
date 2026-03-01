const std = @import("std");
const display = @import("display.zig");
const math = @import("math.zig");
const game = @import("game.zig");
const state = @import("state.zig");
const vx = @import("vx.zig");

pub fn empire() void {
    display.ttinit();
    math.rndini();
    display.clear_screen();
    display.pos_str(@as(c_int, 7), @as(c_int, 0), "EMPIRE, Version 5.00 site Amdahl 1-Apr-1988");
    display.pos_str(@as(c_int, 8), @as(c_int, 0), "Detailed directions are in EMPIRE.DOC\n");
    display.redisplay();
    game.restore() catch {
        game.init();
    };

    // Initialize event-driven state machine
    state.initState();
    state.showIdlePrompt();
    vx.render();

    // Main event loop
    while (true) {
        if (state.hasActiveTimer()) {
            // Timer active: poll events non-blocking and tick
            if (vx.tryEvent()) |event| {
                handleEvent(event);
            }
            state.tick();
            vx.render();
            std.Thread.sleep(16 * std.time.ns_per_ms); // ~60fps
        } else {
            // Idle: block until next event
            const event = vx.nextEvent();
            handleEvent(event);
            vx.render();
        }
    }
}

fn handleEvent(event: vx.Event) void {
    switch (event) {
        .key_press => |key| state.handleKey(key),
        .winsize => |ws| vx.handleResize(ws),
        else => {},
    }
}
