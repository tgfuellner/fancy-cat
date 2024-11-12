// Config file for fancy-cat

pub const KeyMap = struct {
    // Next page
    pub const next = .{ .key = 'j', .modifiers = .{} };
    // Previous page
    pub const prev = .{ .key = 'k', .modifiers = .{} };
    // Quit application
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
};
