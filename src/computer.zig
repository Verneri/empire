extern fn comp_move(nmoves: c_int) void;
pub fn move(nmoves: u8) void {
    comp_move(@intCast(nmoves));
}
