const compmove = @import("compmove.zig");
pub fn move(nmoves: u8) void {
    compmove.comp_move(@intCast(nmoves));
}
