// File monitor will be used to watch for changes to files and rerender them
pub const FileMonitor = struct {
    pub const enabled: bool = true;
    // Amount of time to wait inbetween polling for file changes
    pub const latency: f16 = 0.1;
};

// Cache will be used to cache pages for faster rendering
pub const Cache = struct {
    pub const enabled: bool = true;
    // Maximum amount of recently visited pages to cache
    pub const recent_pages: usize = 1;
    // Maximum amount of pages to cache ahead
    pub const next_pages: usize = 1;
    // Maximum amount of pages to cache behind
    pub const prev_pages: usize = 1;
};
