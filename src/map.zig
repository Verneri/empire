const types = @import("types.zig");
const view_map_t = types.view_map_t;
pub extern fn vmap_at_sea(vmap: [*c]view_map_t, loc: c_long) bool;
