// config
pub const KeyMap = struct {
    pub const next = .{ .key = 'n', .modifiers = .{} };
    pub const prev = .{ .key = 'p', .modifiers = .{} };
    pub const scroll_up = .{ .key = 'k', .modifiers = .{} };
    pub const scroll_down = .{ .key = 'j', .modifiers = .{} };
    pub const scroll_left = .{ .key = 'h', .modifiers = .{} };
    pub const scroll_right = .{ .key = 'l', .modifiers = .{} };
    pub const zoom_in = .{ .key = 'i', .modifiers = .{} };
    pub const zoom_out = .{ .key = 'o', .modifiers = .{} };
    // undo all zooming and scrolling
    pub const undo = .{ .key = 'u', .modifiers = .{} };
    pub const quit = .{ .key = 'c', .modifiers = .{ .ctrl = true } };
};

/// File monitor will be used to watch for changes to files and rerender them
pub const FileMonitor = struct {
    pub const enabled: bool = true;
    // Amount of time to wait inbetween polling for file changes
    pub const latency: f16 = 0.1;
};

pub const Appearance = struct {
    pub const darkmode: bool = false;
    pub const zoom: f32 = 2.0;
    // amount to zoom in/out by
    pub const zoom_step: f32 = 0.25;
    pub const scroll_step: f32 = 25.0;
};
