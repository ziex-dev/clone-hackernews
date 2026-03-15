const std = @import("std");
const zx = @import("zx");

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
        const id = self.next_id;
        self.next_id += 1;

        try self.stories.append(self.allocator, .{
            .id = id,
            .title = title,
            .url = url,
            .text = text,
            .author = author,
            .score = 1,
            .comment_count = 0,
            .time = std.time.timestamp(),
        });

        try self.saveStories();
        return id;
    }

    pub fn addComment(self: *Store, story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8) !usize {
        const id = self.next_id;
        self.next_id += 1;

        try self.comments.put(self.allocator, id, .{
            .id = id,
            .story_id = story_id,
            .parent_id = parent_id,
            .author = author,
            .text = text,
            .time = std.time.timestamp(),
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

        try self.saveComments();
        try self.saveStories();
        return id;
    }

    pub fn vote(self: *Store, username: []const u8, item_id: usize) !void {
        for (self.votes.items) |v| {
            if (std.mem.eql(u8, v.username, username) and v.item_id == item_id) return;
        }

        try self.votes.append(self.allocator, .{
            .username = try self.allocator.dupe(u8, username),
            .item_id = item_id,
        });

        if (self.comments.getPtr(item_id)) |c| {
            c.score += 1;
            try self.saveComments();
        } else {
            for (self.stories.items) |*s| {
                if (s.id == item_id) {
                    s.score += 1;
                    try self.saveStories();
                    break;
                }
            }
        }
        try self.saveVotes();
    }

    pub fn hasVoted(self: *Store, username: []const u8, item_id: usize) bool {
        for (self.votes.items) |v| {
            if (std.mem.eql(u8, v.username, username) and v.item_id == item_id) return true;
        }
        return false;
    }

    pub fn addUser(self: *Store, username: []const u8, password: []const u8) !void {
        const owned_username = try self.allocator.dupe(u8, username);
        try self.users.put(self.allocator, owned_username, .{
            .username = owned_username,
            .password = try self.allocator.dupe(u8, password),
        });
        try self.saveUsers();
    }

    pub fn getUser(self: *Store, username: []const u8) ?User {
        return self.users.get(username);
    }

    pub fn searchStories(self: *Store, allocator: std.mem.Allocator, query: []const u8) ![]Story {
        var list = std.ArrayListUnmanaged(Story){};
        for (self.stories.items) |item| {
            const in_title = std.ascii.indexOfIgnoreCase(item.title, query) != null;
            const in_text = if (item.text) |t| std.ascii.indexOfIgnoreCase(t, query) != null else false;
            if (in_title or in_text) {
                try list.append(self.allocator, item);
            }
        }
        return list.toOwnedSlice(allocator);
    }

    fn saveStories(self: *Store) !void {
        const json = try std.json.Stringify.valueAlloc(self.allocator, self.stories.items, .{});
        try zx.kv.put("stories", json, .{});
    }

    fn saveComments(self: *Store) !void {
        var list: std.ArrayListUnmanaged(Comment) = .empty;
        var it = self.comments.iterator();
        while (it.next()) |entry|
            try list.append(self.allocator, entry.value_ptr.*);
        const json = try std.json.Stringify.valueAlloc(self.allocator, list.items, .{});
        try zx.kv.put("comments", json, .{});
    }

    fn saveUsers(self: *Store) !void {
        var list: std.ArrayListUnmanaged(User) = .empty;
        var it = self.users.iterator();
        while (it.next()) |entry|
            try list.append(self.allocator, entry.value_ptr.*);
        const json = try std.json.Stringify.valueAlloc(self.allocator, list.items, .{});
        try zx.kv.put("users", json, .{});
    }

    fn saveVotes(self: *Store) !void {
        const json = try std.json.Stringify.valueAlloc(self.allocator, self.votes.items, .{});
        try zx.kv.put("votes", json, .{});
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

    load(s, allocator) catch {
        s.stories = .empty;
        s.comments = .empty;
        s.users = .empty;
        s.votes = .empty;
        s.next_id = 1;
    };

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
    if (try zx.kv.get(allocator, "stories")) |json|
        for (try std.json.parseFromSliceLeaky([]Story, allocator, json, .{ .ignore_unknown_fields = true })) |story| {
            try s.stories.append(allocator, story);
            if (story.id >= s.next_id) s.next_id = story.id + 1;
        };

    if (try zx.kv.get(allocator, "comments")) |json|
        for (try std.json.parseFromSliceLeaky([]Comment, allocator, json, .{ .ignore_unknown_fields = true })) |c| {
            try s.comments.put(allocator, c.id, c);
            if (c.id >= s.next_id) s.next_id = c.id + 1;
        };

    if (try zx.kv.get(allocator, "users")) |json|
        for (try std.json.parseFromSliceLeaky([]User, allocator, json, .{ .ignore_unknown_fields = true })) |u|
            try s.users.put(allocator, u.username, u);

    if (try zx.kv.get(allocator, "votes")) |json|
        for (try std.json.parseFromSliceLeaky([]Vote, allocator, json, .{ .ignore_unknown_fields = true })) |v|
            try s.votes.append(allocator, v);
}
