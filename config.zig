// If enabled, the file monitor will be used to watch for changes to files and rerender them.
pub const FileMonitor = struct {
    pub const enabled: bool = true;
    // Amount of time to wait inbetween polling for file changes.
    pub const latency: f16 = 0.1;
};
