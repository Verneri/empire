pub extern fn prompt(fmt: [*c]const u8, ...) void;
pub extern fn get_chx() u8;
extern fn @"error"(fmt: [*c]const u8, ...) void;
pub extern fn huh() void;
pub extern fn help(text: [*c][*c]u8, nlines: c_int) void;
pub extern fn getint(message: [*c]const u8) c_int;
pub extern fn comment(fmt: [*c]const u8, ...) void;
pub extern fn ksend(fmt: [*c]const u8, ...) void;
pub extern fn getyn(message: [*c]const u8) bool;
pub extern fn get_range(message: [*c]const u8, low: c_int, high: c_int) c_int;
pub extern fn get_str(buf: [*c]u8, sizep: c_int) void;
pub extern fn loc_disp(loc: c_int) c_int;
pub extern fn topini() void;

pub fn error_msg(fmt: [*c]const u8) void {
    @"error"(fmt);
}

pub fn fmt_error(fmt: [*c]const u8, args: anytype) void {
    @call(.auto, @"error", .{fmt} ++ args);
}
