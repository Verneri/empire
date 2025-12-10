const std = @import("std");

const empire = @import("empire.zig");
const globals = @import("globals.zig");

//unistd.h
pub extern fn getopt(c_int, [*c]const [*c]u8, [*c]const u8) c_int;

pub extern var optarg: [*c]u8;

//stdlib.h
pub extern fn atoi([*c]const u8) c_int;

const Cargs = struct {
    contents: []u8,
    slices: [][*:0]u8,

    pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.slices);
        alloc.free(self.contents);
    }

    pub fn init(alloc: std.mem.Allocator) !@This() {
        var args = std.process.args();

        var contents = std.array_list.Managed(u8).init(alloc);
        var starts: std.array_list.Managed(usize) = std.array_list.Managed(usize).init(alloc);
        var ends: std.array_list.Managed(usize) = std.array_list.Managed(usize).init(alloc);
        defer starts.deinit();
        defer ends.deinit();
        var slices = std.array_list.Managed([*:0]u8).init(alloc);
        while (args.next()) |arg| {
            const start = contents.items.len;
            try contents.appendSlice(arg);
            contents.appendAssumeCapacity(0);
            //const slice = contents.items[start .. start + arg.len + 1];
            try starts.append(start);
            try ends.append(start + arg.len + 1);
        }
        const content_slice = try contents.toOwnedSlice();
        for (starts.items, ends.items) |start, end| {
            const slice: []u8 = content_slice[start..end];
            try slices.append(@ptrCast(slice.ptr));
        }
        const cargs = Cargs{
            .contents = content_slice,
            .slices = try slices.toOwnedSlice(),
        };
        return cargs;
    }

    pub fn argc(self: *const @This()) c_int {
        return @intCast(self.slices.len);
    }

    pub fn argv(self: *const @This()) [*][*:0]u8 {
        return self.slices.ptr;
    }

    pub fn get_opt(self: *const @This(), opts: []const u8) ?u8 {
        const res = getopt(self.argc(), self.argv(), opts.ptr);
        if (res == -1) return null;
        return @intCast(res);
    }
};

pub fn get_arg() ?[*:0]u8 {
    return optarg;
}

pub fn get_int_arg() ?i32 {
    if (get_arg()) |arg| {
        return atoi(arg);
    } else return null;
}

const ParameterError = error{UnknownParameter};

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var cargs = try Cargs.init(alloc);
    defer cargs.deinit(alloc);

    var wflg: i32 = 70;
    var sflg: i32 = 5;
    var dflg: i32 = 2000;
    var siflg: i32 = 10;

    var savef: ?[*:0]u8 = null;

    var errorflag = false;

    while (cargs.get_opt("w:s:d:S:f:")) |opt| {
        switch (opt) {
            'w' => wflg = get_int_arg().?,
            's' => sflg = get_int_arg().?,
            'd' => dflg = get_int_arg().?,
            'S' => siflg = get_int_arg().?,
            'f' => savef = get_arg().?,
            '?' => errorflag = true,
            else => unreachable,
        }
    }

    if (errorflag) {
        std.debug.print("empire: usage: empire [-w water] [-s smooth] [-d delay]\n", .{});
        std.c.exit(1);
    }

    var default_savefile_buf = std.array_list.Managed(u8).init(alloc);
    try default_savefile_buf.appendSlice("empsave.dat");
    try default_savefile_buf.append(0);
    const default_save = try default_savefile_buf.toOwnedSlice();
    defer alloc.free(default_save);

    var save: [:0]u8 = @ptrCast(default_save);
    if (savef) |file| {
        var end: usize = 0;
        while (file[end] != 0) : (end += 1) {}
        save = @ptrCast(file[0 .. end + 1]);
    }

    var save_interval: u16 = undefined;
    if (siflg > 0) {
        save_interval = @intCast(siflg);
    } else {
        std.debug.print("empire: -S argument must be greater or equal to zero.\n", .{});
        std.c.exit(1);
    }

    start_game(sflg, wflg, dflg, save_interval, save);
}

pub fn start_game(sflg: i32, wflg: i32, dflg: i32, siflg: u16, save: [:0]u8) void {
    globals.SMOOTH = sflg;
    globals.WATER_RATIO = wflg;
    globals.delay_time = dflg;
    globals.save_interval = siflg;

    globals.savefile = save.ptr;

    var land: u32 = @intCast(@divTrunc(globals.MAP_SIZE * (100 - globals.WATER_RATIO), 100)); // available land
    land = @divTrunc(land, globals.NUM_CITY); // land per city
    globals.MIN_CITY_DIST = std.math.sqrt(land); // distance betwen cities

    std.debug.print("water ratio: {}%\n", .{globals.WATER_RATIO});
    std.debug.print("smooth: {}\n", .{globals.SMOOTH});
    std.debug.print("delay time: {}\n", .{globals.delay_time});
    std.debug.print("save interval: {}\n", .{globals.save_interval});
    std.debug.print("savefile: {s}\n", .{globals.savefile});
    std.debug.print("land per city: {}\n", .{land});
    std.debug.print("min city dist: {}\n", .{globals.MIN_CITY_DIST});

    empire.empire();
}
