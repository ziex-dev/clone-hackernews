const std = @import("std");
const zx = @import("zx");
const query = @import("query.zig");

pub const Story = struct {
    id: usize,
    title: []const u8,
    url: ?[]const u8 = null,
    text: ?[]const u8 = null,
    author: []const u8,
    score: i32,
    comment_count: usize,
    time: i64,
};

pub const Comment = struct {
    id: usize,
    story_id: usize,
    parent_id: ?usize = null,
    author: []const u8,
    text: []const u8,
    time: i64,
    score: i32 = 1,
    replies: []usize = &.{},
};

pub const Vote = struct {
    username: []const u8,
    item_id: usize,
};

pub const User = struct {
    username: []const u8,
    password: []const u8,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    stories: std.ArrayListUnmanaged(Story),
    comments: std.AutoHashMapUnmanaged(usize, Comment),
    users: std.StringHashMapUnmanaged(User),
    votes: std.ArrayListUnmanaged(Vote),
    next_id: usize,

    pub fn addStory(self: *Store, title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8) !usize {
        const time = std.time.timestamp();
        const rowid = try query.insertStory(title, url, text, author, time);
        const id: usize = @intCast(rowid);

        try self.stories.append(self.allocator, .{
            .id = id,
            .title = title,
            .url = url,
            .text = text,
            .author = author,
            .score = 1,
            .comment_count = 0,
            .time = time,
        });

        if (id >= self.next_id) self.next_id = id + 1;
        return id;
    }

    pub fn addComment(self: *Store, story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8) !usize {
        const time = std.time.timestamp();
        const rowid = try query.insertComment(story_id, parent_id, author, text, time);
        const id: usize = @intCast(rowid);

        try self.comments.put(self.allocator, id, .{
            .id = id,
            .story_id = story_id,
            .parent_id = parent_id,
            .author = author,
            .text = text,
            .time = time,
            .score = 1,
        });

        if (parent_id) |p_id| {
            if (self.comments.getPtr(p_id)) |p| {
                const new_replies = try self.allocator.realloc(p.replies, p.replies.len + 1);
                new_replies[new_replies.len - 1] = id;
                p.replies = new_replies;
            }
        }

        for (self.stories.items) |*story| {
            if (story.id == story_id) {
                story.comment_count += 1;
                break;
            }
        }

        if (id >= self.next_id) self.next_id = id + 1;
        return id;
    }

    pub fn vote(self: *Store, username: []const u8, item_id: usize) !void {
        if (try query.hasVoted(self.allocator, username, item_id)) return;

        try query.insertVote(username, item_id);

        if (try query.isComment(self.allocator, item_id)) {
            try query.upvoteComment(item_id);
            if (self.comments.getPtr(item_id)) |c| {
                c.score += 1;
            }
        } else {
            try query.upvoteStory(item_id);
            for (self.stories.items) |*s| {
                if (s.id == item_id) {
                    s.score += 1;
                    break;
                }
            }
        }

        try self.votes.append(self.allocator, .{
            .username = try self.allocator.dupe(u8, username),
            .item_id = item_id,
        });
    }

    pub fn hasVoted(self: *Store, username: []const u8, item_id: usize) bool {
        return query.hasVoted(self.allocator, username, item_id) catch false;
    }

    pub fn addUser(self: *Store, username: []const u8, password: []const u8) !void {
        try query.insertUser(username, password);
        const owned_username = try self.allocator.dupe(u8, username);
        try self.users.put(self.allocator, owned_username, .{
            .username = owned_username,
            .password = try self.allocator.dupe(u8, password),
        });
    }

    pub fn getUser(self: *Store, username: []const u8) ?User {
        return self.users.get(username);
    }

    pub fn searchStories(self: *Store, allocator: std.mem.Allocator, search_query: []const u8) ![]Story {
        var list = std.ArrayListUnmanaged(Story){};
        for (self.stories.items) |item| {
            const in_title = std.ascii.indexOfIgnoreCase(item.title, search_query) != null;
            const in_text = if (item.text) |t| std.ascii.indexOfIgnoreCase(t, search_query) != null else false;
            if (in_title or in_text) {
                try list.append(self.allocator, item);
            }
        }
        return list.toOwnedSlice(allocator);
    }
};

pub fn get(allocator: std.mem.Allocator) !*Store {
    const s = try allocator.create(Store);
    s.* = .{
        .allocator = allocator,
        .stories = .empty,
        .comments = .empty,
        .users = .empty,
        .votes = .empty,
        .next_id = 1,
    };

    // Initialize DB tables
    try query.init();

    // Load from DB
    try load(s, allocator);

    // Seed if empty
    if (s.stories.items.len == 0) {
        _ = try s.addStory("Ziex: A full-stack web framework for Zig", null, null, "nurulhudaapon");
        _ = try s.addStory("Show HN: Exact Hacker News Clone in Ziex", null, "I built this clone to show off Ziex.", "nurulhudaapon");
        _ = try s.addStory("Zig 0.15.2 Released", "https://ziglang.org/download/0.15.1/release-notes.html", null, "andrewrk");

        const story1_id = s.stories.items[0].id;
        const c1_id = try s.addComment(story1_id, null, "user1", "This looks amazing!");
        _ = try s.addComment(story1_id, null, "user2", "Zig is the future of web dev.");
        _ = try s.addComment(story1_id, c1_id, "user3", "I agree!");
    }

    return s;
}

fn load(s: *Store, allocator: std.mem.Allocator) !void {
    // Load stories
    const story_rows = try query.allStories(allocator);
    for (story_rows) |row| {
        const id: usize = @intCast(asInt(row, "id"));
        try s.stories.append(allocator, .{
            .id = id,
            .title = asText(row, "title"),
            .url = asOptionalText(row, "url"),
            .text = asOptionalText(row, "text"),
            .author = asText(row, "author"),
            .score = @intCast(asInt(row, "score")),
            .comment_count = @intCast(asInt(row, "comment_count")),
            .time = asInt(row, "time"),
        });
        if (id >= s.next_id) s.next_id = id + 1;
    }

    // Load comments
    const comment_rows = try query.allComments(allocator);
    for (comment_rows) |row| {
        const id: usize = @intCast(asInt(row, "id"));
        const parent_id_val = asInt(row, "parent_id");
        const parent_id: ?usize = if (parent_id_val > 0) @intCast(parent_id_val) else null;

        // Get replies for this comment
        const reply_rows = try query.commentReplies(allocator, id);
        var replies = try allocator.alloc(usize, reply_rows.len);
        for (reply_rows, 0..) |reply_row, i| {
            replies[i] = @intCast(asInt(reply_row, "id"));
        }

        try s.comments.put(allocator, id, .{
            .id = id,
            .story_id = @intCast(asInt(row, "story_id")),
            .parent_id = parent_id,
            .author = asText(row, "author"),
            .text = asText(row, "text"),
            .time = asInt(row, "time"),
            .score = @intCast(asInt(row, "score")),
            .replies = replies,
        });
        if (id >= s.next_id) s.next_id = id + 1;
    }

    // Load users
    const user_rows = try allUsers(allocator);
    for (user_rows) |row| {
        const username = asText(row, "username");
        try s.users.put(allocator, username, .{
            .username = username,
            .password = asText(row, "password"),
        });
    }

    // Load votes
    const vote_rows = try allVotes(allocator);
    for (vote_rows) |row| {
        try s.votes.append(allocator, .{
            .username = asText(row, "username"),
            .item_id = @intCast(asInt(row, "item_id")),
        });
    }
}

fn allUsers(allocator: std.mem.Allocator) ![]const zx.db.Row {
    var stmt = try zx.db.query("SELECT username, password FROM users");
    defer stmt.deinit();
    return try stmt.all(allocator, .empty);
}

fn allVotes(allocator: std.mem.Allocator) ![]const zx.db.Row {
    var stmt = try zx.db.query("SELECT username, item_id FROM votes");
    defer stmt.deinit();
    return try stmt.all(allocator, .empty);
}

fn asInt(row: zx.db.Row, name: []const u8) i64 {
    return switch (row.get(name) orelse .null) {
        .integer => |value| value,
        .float => |value| @intFromFloat(value),
        else => 0,
    };
}

fn asText(row: zx.db.Row, name: []const u8) []const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => "",
    };
}

fn asOptionalText(row: zx.db.Row, name: []const u8) ?[]const u8 {
    return switch (row.get(name) orelse .null) {
        .text => |value| value,
        else => null,
    };
}
