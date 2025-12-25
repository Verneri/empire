const types = @import("types.zig");
pub extern fn scan(vmap: [*c]types.view_map_t, loc: c_long) void;
