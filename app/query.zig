const zx = @import("zx");

const db = zx.db;
const Bindings = db.Bindings;
const Value = db.Value;
const Row = db.Row;

pub fn init() !void {
    _ = try db.run(
        \\CREATE TABLE IF NOT EXISTS stories (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  title TEXT NOT NULL,
        \\  url TEXT,
        \\  text TEXT,
        \\  author TEXT NOT NULL,
        \\  score INTEGER NOT NULL DEFAULT 1,
        \\  comment_count INTEGER NOT NULL DEFAULT 0,
        \\  time INTEGER NOT NULL
        \\)
    , .empty);

    _ = try db.run(
        \\CREATE TABLE IF NOT EXISTS comments (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  story_id INTEGER NOT NULL,
        \\  parent_id INTEGER,
        \\  author TEXT NOT NULL,
        \\  text TEXT NOT NULL,
        \\  time INTEGER NOT NULL,
        \\  score INTEGER NOT NULL DEFAULT 1
        \\)
    , .empty);

    _ = try db.run(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  username TEXT PRIMARY KEY,
        \\  password TEXT NOT NULL
        \\)
    , .empty);

    _ = try db.run(
        \\CREATE TABLE IF NOT EXISTS votes (
        \\  username TEXT NOT NULL,
        \\  item_id INTEGER NOT NULL,
        \\  PRIMARY KEY (username, item_id)
        \\)
    , .empty);
}

pub fn storyCount(allocator: std.mem.Allocator) !i64 {
    var stmt = try db.query("SELECT COUNT(*) AS cnt FROM stories");
    defer stmt.deinit();
    const row = (try stmt.get(allocator, .empty)) orelse return 0;
    return asInt(row, "cnt");
}

pub fn insertStory(title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8, time: i64) !i64 {
    const result = try db.run(
        "INSERT INTO stories (title, url, text, author, time) VALUES (?, ?, ?, ?, ?)",
        .{ .positional = &.{
            .{ .text = title },
            if (url) |u| Value{ .text = u } else .null,
            if (text) |t| Value{ .text = t } else .null,
            .{ .text = author },
            .{ .integer = time },
        } },
    );
    return result.last_insert_rowid;
}

pub fn insertComment(story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8, time: i64) !i64 {
    const result = try db.run(
        "INSERT INTO comments (story_id, parent_id, author, text, time) VALUES (?, ?, ?, ?, ?)",
        .{ .positional = &.{
            .{ .integer = @intCast(story_id) },
            if (parent_id) |p| Value{ .integer = @intCast(p) } else .null,
            .{ .text = author },
            .{ .text = text },
            .{ .integer = time },
        } },
    );

    // Increment comment_count on the story
    _ = try db.run(
        "UPDATE stories SET comment_count = comment_count + 1 WHERE id = ?",
        .{ .positional = &.{.{ .integer = @intCast(story_id) }} },
    );

    return result.last_insert_rowid;
}

pub fn insertUser(username: []const u8, password: []const u8) !void {
    _ = try db.run(
        "INSERT OR IGNORE INTO users (username, password) VALUES (?, ?)",
        .{ .positional = &.{
            .{ .text = username },
            .{ .text = password },
        } },
    );
}

pub fn getUser(allocator: zx.Allocator, username: []const u8) !?struct { username: []const u8, password: []const u8 } {
    var stmt = try db.prepare("SELECT username, password FROM users WHERE username = ?");
    defer stmt.deinit();
    const row = (try stmt.get(allocator, .{ .positional = &.{.{ .text = username }} })) orelse return null;
    return .{
        .username = asText(row, "username"),
        .password = asText(row, "password"),
    };
}

pub fn insertVote(username: []const u8, item_id: usize) !void {
    _ = try db.run(
        "INSERT OR IGNORE INTO votes (username, item_id) VALUES (?, ?)",
        .{ .positional = &.{
            .{ .text = username },
            .{ .integer = @intCast(item_id) },
        } },
    );
}

pub fn hasVoted(allocator: zx.Allocator, username: []const u8, item_id: usize) !bool {
    var stmt = try db.prepare("SELECT 1 AS found FROM votes WHERE username = ? AND item_id = ?");
    defer stmt.deinit();
    const row = try stmt.get(allocator, .{ .positional = &.{
        .{ .text = username },
        .{ .integer = @intCast(item_id) },
    } });
    return row != null;
}

pub fn upvoteStory(item_id: usize) !void {
    _ = try db.run(
        "UPDATE stories SET score = score + 1 WHERE id = ?",
        .{ .positional = &.{.{ .integer = @intCast(item_id) }} },
    );
}

pub fn upvoteComment(item_id: usize) !void {
    _ = try db.run(
        "UPDATE comments SET score = score + 1 WHERE id = ?",
        .{ .positional = &.{.{ .integer = @intCast(item_id) }} },
    );
}

pub fn isComment(allocator: zx.Allocator, item_id: usize) !bool {
    var stmt = try db.prepare("SELECT 1 AS found FROM comments WHERE id = ?");
    defer stmt.deinit();
    const row = try stmt.get(allocator, .{ .positional = &.{.{ .integer = @intCast(item_id) }} });
    return row != null;
}

pub fn allStories(allocator: zx.Allocator) ![]const Row {
    var stmt = try db.query("SELECT id, title, url, text, author, score, comment_count, time FROM stories ORDER BY id ASC");
    defer stmt.deinit();
    return try stmt.all(allocator, .empty);
}

pub fn allComments(allocator: zx.Allocator) ![]const Row {
    var stmt = try db.query("SELECT id, story_id, parent_id, author, text, time, score FROM comments ORDER BY id ASC");
    defer stmt.deinit();
    return try stmt.all(allocator, .empty);
}

pub fn commentReplies(allocator: zx.Allocator, parent_id: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id FROM comments WHERE parent_id = ? ORDER BY id ASC");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{.{ .integer = @intCast(parent_id) }} });
}

pub fn searchStories(allocator: zx.Allocator, search_query: []const u8) ![]const Row {
    var stmt = try db.prepare(
        "SELECT id, title, url, text, author, score, comment_count, time FROM stories WHERE title LIKE '%' || ? || '%' OR text LIKE '%' || ? || '%'",
    );
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .text = search_query },
        .{ .text = search_query },
    } });
}

pub fn storiesByScore(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories ORDER BY score DESC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn storiesByNewest(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories ORDER BY id DESC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn storiesByOldest(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories ORDER BY time ASC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn storiesByTitlePrefix(allocator: std.mem.Allocator, prefix: []const u8, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories WHERE title LIKE ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .text = prefix },
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn storiesByTitleKeywords(allocator: std.mem.Allocator, kw1: []const u8, kw2: []const u8, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories WHERE title LIKE '%' || ? || '%' OR title LIKE '%' || ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .text = kw1 },
        .{ .text = kw2 },
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn paginatedSearchStories(allocator: std.mem.Allocator, search_query: []const u8, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare(
        "SELECT id, title, url, text, author, score, comment_count, time FROM stories WHERE title LIKE '%' || ? || '%' OR text LIKE '%' || ? || '%' ORDER BY id DESC LIMIT ? OFFSET ?",
    );
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .text = search_query },
        .{ .text = search_query },
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

pub fn storyByIdQuery(allocator: std.mem.Allocator, id: usize) !?Row {
    var stmt = try db.prepare("SELECT id, title, url, text, author, score, comment_count, time FROM stories WHERE id = ?");
    defer stmt.deinit();
    return try stmt.get(allocator, .{ .positional = &.{.{ .integer = @intCast(id) }} });
}

pub fn commentsForStoryQuery(allocator: std.mem.Allocator, story_id: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, story_id, parent_id, author, text, time, score FROM comments WHERE story_id = ? ORDER BY id ASC");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{.{ .integer = @intCast(story_id) }} });
}

pub fn commentByIdQuery(allocator: std.mem.Allocator, id: usize) !?Row {
    var stmt = try db.prepare("SELECT id, story_id, parent_id, author, text, time, score FROM comments WHERE id = ?");
    defer stmt.deinit();
    return try stmt.get(allocator, .{ .positional = &.{.{ .integer = @intCast(id) }} });
}

pub fn commentsPaginated(allocator: std.mem.Allocator, limit: usize, offset: usize) ![]const Row {
    var stmt = try db.prepare("SELECT id, story_id, parent_id, author, text, time, score FROM comments ORDER BY time DESC LIMIT ? OFFSET ?");
    defer stmt.deinit();
    return try stmt.all(allocator, .{ .positional = &.{
        .{ .integer = @intCast(limit) },
        .{ .integer = @intCast(offset) },
    } });
}

const std = @import("std");

fn asInt(row: Row, name: []const u8) i64 {
    return switch (row.get(name) orelse .null) {
        .integer => |value| value,
        .float => |value| @intFromFloat(value),
        else => 0,
    };
}

fn asText(row: Row, name: []const u8) []const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => "",
    };
}
