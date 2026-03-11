const std = @import("std");
const globals = @import("globals.zig");
const util = @import("util.zig");

var rng: std.Random.DefaultPrng = undefined;

pub fn rndini() void {
    const seed: u64 = @bitCast(std.time.timestamp());
    rng = std.Random.DefaultPrng.init(seed);
}

pub fn irand(high: i64) i64 {
    if (high < 2) return 0;
    return @intCast(rng.random().uintLessThan(u64, @intCast(high)));
}

pub fn dist(a: i64, b: i64) i32 {
    const ax = util.loc_row(a);
    const ay = util.loc_col(a);
    const bx = util.loc_row(b);
    const by = util.loc_col(b);

    return @intCast(@max(@abs(ax - bx), @abs(ay - by)));
}

pub fn isqrt(n: i32) i32 {
    std.debug.assert(n >= 0);

    if (n <= 1) return n;

    var guess: i32 = 2;
    guess = @divTrunc(guess + @divTrunc(n, guess), 2);
    guess = @divTrunc(guess + @divTrunc(n, guess), 2);
    guess = @divTrunc(guess + @divTrunc(n, guess), 2);
    guess = @divTrunc(guess + @divTrunc(n, guess), 2);
    guess = @divTrunc(guess + @divTrunc(n, guess), 2);

    if (guess * guess > n) guess -= 1;
    return guess;
}
