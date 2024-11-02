const std = @import("std");
const config = @import("config").Config;
const Encoder = std.base64.standard.Encoder;
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
    @cInclude("termios.h");
    @cInclude("sys/ioctl.h");
});

const RenderBuffer = struct {
    base64_data: []u8,
    width: c_int,
    height: c_int,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RenderBuffer {
        return .{
            .base64_data = &[_]u8{},
            .width = 0,
            .height = 0,
            .allocator = allocator,
        };
    }

    pub fn update(
        self: *RenderBuffer,
        new_data: []const u8,
        new_width: c_int,
        new_height: c_int,
    ) !void {
        // Free existing data if any
        if (self.base64_data.len > 0) {
            self.allocator.free(self.base64_data);
        }

        // Allocate and copy new data
        self.base64_data = try self.allocator.dupe(u8, new_data);
        self.width = new_width;
        self.height = new_height;
    }

    pub fn deinit(self: *RenderBuffer) void {
        if (self.base64_data.len > 0) {
            self.allocator.free(self.base64_data);
        }
    }
};

/// Terminal size information
const TerminalSize = struct {
    width: u16,
    height: u16,

    pub fn get() !TerminalSize {
        var size: c.struct_winsize = undefined;
        if (c.ioctl(1, c.TIOCGWINSZ, &size) == -1) {
            return error.FailedToGetTerminalSize;
        }
        const width = @as(u16, size.ws_col) * 10;
        const height = @as(u16, size.ws_row) * 20;
        return TerminalSize{
            .width = width,
            .height = height,
        };
    }
};

/// Stores the original terminal settings
const TerminalState = struct {
    original_termios: c.termios,

    pub fn init() !TerminalState {
        var original_termios: c.termios = undefined;
        if (c.tcgetattr(0, &original_termios) != 0) {
            return error.TermiosGetAttrFailed;
        }

        var raw = original_termios;
        raw.c_lflag &= ~@as(c_uint, c.ICANON | c.ECHO);
        raw.c_cc[c.VMIN] = 1;
        raw.c_cc[c.VTIME] = 0;

        if (c.tcsetattr(0, c.TCSAFLUSH, &raw) != 0) {
            return error.TermiosSetAttrFailed;
        }

        return TerminalState{
            .original_termios = original_termios,
        };
    }

    pub fn deinit(self: *const TerminalState) void {
        _ = c.tcsetattr(0, c.TCSAFLUSH, &self.original_termios);
    }
};

/// Stores file monitoring state
const FileMonitor = struct {
    path: []const u8,
    last_modified: i128,
    allocator: std.mem.Allocator,

    /// Initialize file monitor
    pub fn init(path: []const u8, allocator: std.mem.Allocator) !FileMonitor {
        const last_modified = try getFileModTime(path);
        return FileMonitor{
            .path = try allocator.dupe(u8, path),
            .last_modified = last_modified,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileMonitor) void {
        self.allocator.free(self.path);
    }

    /// Check if file has been modified
    pub fn hasChanged(self: *FileMonitor) !bool {
        const current_modified = try getFileModTime(self.path);
        const changed = current_modified != self.last_modified;
        self.last_modified = current_modified;
        return changed;
    }

    /// Get file modification time
    fn getFileModTime(path: []const u8) !i128 {
        const file = try std.fs.cwd().statFile(path);
        return file.mtime;
    }
};

/// Creates and initializes a new MuPDF context
fn createContext() !*c.fz_context {
    const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse
        return error.ContextCreationFailed;
    c.fz_register_document_handlers(ctx);
    return ctx;
}

/// Opens a PDF document from the given path
fn openDocument(ctx: *c.fz_context, path: []const u8) !*c.fz_document {
    const doc = c.fz_open_document(ctx, path.ptr) orelse {
        const err_msg = c.fz_caught_message(ctx);
        std.debug.print("Failed to open document: {s}\n", .{err_msg});
        return error.FailedToOpenDocument;
    };
    return doc;
}

/// Calculate scale factor to fit page in terminal
fn calculateScale(
    ctx: *c.fz_context,
    doc: *c.fz_document,
    page_number: i32,
    term_size: TerminalSize,
) !f32 {
    const page = c.fz_load_page(ctx, doc, page_number) orelse
        return error.PageLoadFailed;
    defer c.fz_drop_page(ctx, page);

    const bounds = c.fz_bound_page(ctx, page);
    const page_width = bounds.x1 - bounds.x0;
    const page_height = bounds.y1 - bounds.y0;

    const padding_factor: f32 = 1.2;
    const width_scale = (@as(f32, @floatFromInt(term_size.width)) / page_width) * padding_factor;
    const height_scale = (@as(f32, @floatFromInt(term_size.height)) / page_height) * padding_factor;

    return @min(width_scale, height_scale);
}

/// Creates a pixmap from the specified page of the document
fn createPixmap(
    ctx: *c.fz_context,
    doc: *c.fz_document,
    page_number: i32,
    scale: f32,
) !*c.fz_pixmap {
    var ctm = c.fz_scale(scale, scale);
    ctm = c.fz_pre_translate(ctm, 20, 20);
    ctm = c.fz_pre_rotate(ctm, 0);

    const pix = c.fz_new_pixmap_from_page_number(
        ctx,
        doc,
        page_number,
        ctm,
        c.fz_device_rgb(ctx),
        0,
    ) orelse return error.PixmapCreationFailed;

    return pix;
}

/// Converts pixmap to PNG buffer
fn pixmapToPngBuffer(
    ctx: *c.fz_context,
    pix: *c.fz_pixmap,
) !*c.fz_buffer {
    return c.fz_new_buffer_from_pixmap_as_png(
        ctx,
        pix,
        c.fz_default_color_params,
    ) orelse return error.BufferCreationFailed;
}

/// Extracts raw data from buffer and converts to base64
fn bufferToBase64(
    ctx: *c.fz_context,
    buf: *c.fz_buffer,
    allocator: std.mem.Allocator,
) ![]u8 {
    var data_ptr: [*c]u8 = undefined;
    const size = c.fz_buffer_extract(ctx, buf, &data_ptr);
    defer c.fz_free(ctx, data_ptr);

    const base64_size = Encoder.calcSize(size);
    const base64_buf = try allocator.alloc(u8, base64_size);
    _ = Encoder.encode(base64_buf, data_ptr[0..size]);

    return base64_buf;
}

/// Writes base64 data to stdout using Kitty Graphics Protocol
fn writeKittyGraphicsProtocol(
    writer: anytype,
    buffer: *const RenderBuffer,
    current_page: i32,
    total_pages: i32,
) !void {
    try writer.writeAll("\x1b[?25l");
    try writer.writeAll("\x1b[H");

    var pos: usize = 0;
    const chunk_size: usize = 4096;

    while (pos < buffer.base64_data.len) {
        const remaining = buffer.base64_data.len - pos;
        const chunk_len = @min(chunk_size, remaining);
        const chunk = buffer.base64_data[pos .. pos + chunk_len];
        const is_last_chunk = (pos + chunk_len == buffer.base64_data.len);

        try writer.writeAll("\x1b_G");
        if (pos == 0) {
            try writer.print("a=T,f=100,s={d},v={d},", .{ buffer.width, buffer.height });
        }

        if (!is_last_chunk) {
            try writer.writeAll("m=1;");
        } else {
            try writer.writeAll(";");
        }

        try writer.writeAll(chunk);
        try writer.writeAll("\x1b\\");
        pos += chunk_len;
    }

    // Update status line
    try writer.print("\x1b[{d};0H", .{buffer.height + 1});
    try writer.print("Page {d}/{d} | Press 'j' next page, 'k' previous page, 'q' to quit", .{ current_page + 1, total_pages });
    try writer.writeAll("\x1b[?25h");
}

/// Reads a single character from stdin
fn readChar() !u8 {
    const stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;
    const bytes_read = try stdin.read(&buf);
    if (bytes_read != 1) return error.ReadError;
    return buf[0];
}

/// Read a character with timeout in milliseconds
fn readCharTimeout(timeout_ms: i32) !?u8 {
    const stdin = std.io.getStdIn();
    var fds = [1]std.posix.pollfd{
        .{
            .fd = stdin.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    const ready = try std.posix.poll(&fds, timeout_ms);
    if (ready == 0) return null;

    var buf: [1]u8 = undefined;
    const bytes_read = try stdin.read(&buf);
    if (bytes_read != 1) return error.ReadError;
    return buf[0];
}

/// Renders the current page
fn renderPage(
    ctx: *c.fz_context,
    doc: *c.fz_document,
    page_number: i32,
    buffer: *RenderBuffer,
    term_size: TerminalSize,
) !void {
    const scale = try calculateScale(ctx, doc, page_number, term_size);

    const pix = try createPixmap(ctx, doc, page_number, scale);
    defer c.fz_drop_pixmap(ctx, pix);

    const width = c.fz_pixmap_width(ctx, pix);
    const height = c.fz_pixmap_height(ctx, pix);

    const png_buf = try pixmapToPngBuffer(ctx, pix);
    defer c.fz_drop_buffer(ctx, png_buf);

    const base64_buf = try bufferToBase64(ctx, png_buf, buffer.allocator);
    errdefer buffer.allocator.free(base64_buf);

    try buffer.update(base64_buf, width, height);
}

// Main entrypoint
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Usage: cat-pdf <path-to-pdf> <optional-page-number>\n");
        return error.InvalidArguments;
    }

    const path = args[1];
    const allocator = std.heap.page_allocator;

    var monitor: ?FileMonitor = if (comptime config.file_monitor) blk: {
        break :blk try FileMonitor.init(path, allocator);
    } else null;
    defer if (monitor) |*m| m.deinit();

    const term_state = try TerminalState.init();
    defer term_state.deinit();

    const ctx = try createContext();
    defer c.fz_drop_context(ctx);

    var current_doc = try openDocument(ctx, path);
    defer c.fz_drop_document(ctx, current_doc);

    const total_pages = c.fz_count_pages(ctx, current_doc);
    var current_page = if (args.len > 2) blk: {
        const num = try std.fmt.parseInt(i32, args[2], 10);
        if ((num < 1) or (num > total_pages)) break :blk 0;
        break :blk num - 1;
    } else 0;

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\x1b[2J\x1b[H");

    var render_buffer = RenderBuffer.init(allocator);
    defer render_buffer.deinit();

    const initial_term_size = try TerminalSize.get();
    try renderPage(ctx, current_doc, current_page, &render_buffer, initial_term_size);
    try writeKittyGraphicsProtocol(stdout, &render_buffer, current_page, total_pages);

    while (true) {
        if (comptime config.file_monitor) {
            if (monitor) |*m| {
                if (try m.hasChanged()) {
                    const term_size = try TerminalSize.get();
                    c.fz_drop_document(ctx, current_doc);
                    current_doc = try openDocument(ctx, path);
                    try renderPage(ctx, current_doc, current_page, &render_buffer, term_size);
                    try writeKittyGraphicsProtocol(stdout, &render_buffer, current_page, total_pages);
                }
            }
        }
        if (try readCharTimeout(100)) |ch| {
            switch (ch) {
                'q' => break,
                'j' => if (current_page < total_pages - 1) {
                    current_page += 1;
                    const term_size = try TerminalSize.get();
                    try renderPage(ctx, current_doc, current_page, &render_buffer, term_size);
                    try writeKittyGraphicsProtocol(stdout, &render_buffer, current_page, total_pages);
                },
                'k' => if (current_page > 0) {
                    current_page -= 1;
                    const term_size = try TerminalSize.get();
                    try renderPage(ctx, current_doc, current_page, &render_buffer, term_size);
                    try writeKittyGraphicsProtocol(stdout, &render_buffer, current_page, total_pages);
                },
                else => {},
            }
        }
    }

    try stdout.writeAll("\x1b[2J\x1b[H");
}
