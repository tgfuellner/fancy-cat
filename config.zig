pub const Config = struct {
    // If enabled, the file monitor will be used to watch for changes to files
    pub const file_monitor: bool = true;
    // if enabled, the next/previous cache_size pages will be kept in memory
    pub const cache: bool = true;
    pub const cache_size: usize = 1;
};
