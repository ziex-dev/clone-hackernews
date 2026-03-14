const std = @import("std");

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
    replies: std.ArrayListUnmanaged(usize),
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    stories: std.ArrayListUnmanaged(Story),
    comments: std.AutoHashMapUnmanaged(usize, Comment),
    next_id: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .stories = .{},
            .comments = .{},
            .next_id = 1,
            .mutex = .{},
        };
    }

    pub fn addStory(self: *Store, title: []const u8, url: ?[]const u8, text: ?[]const u8, author: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

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

        return id;
    }

    pub fn addComment(self: *Store, story_id: usize, parent_id: ?usize, author: []const u8, text: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = self.next_id;
        self.next_id += 1;

        try self.comments.put(self.allocator, id, .{
            .id = id,
            .story_id = story_id,
            .parent_id = parent_id,
            .author = author,
            .text = text,
            .time = std.time.timestamp(),
            .replies = .{},
        });

        if (parent_id) |p_id| {
            if (self.comments.getPtr(p_id)) |p| {
                try p.replies.append(self.allocator, id);
            }
        }

        for (self.stories.items) |*story| {
            if (story.id == story_id) {
                story.comment_count += 1;
                break;
            }
        }

        return id;
    }
};

var global_store: ?*Store = null;

pub fn get(allocator: std.mem.Allocator) !*Store {
    if (global_store) |s| return s;

    const s = try allocator.create(Store);
    s.* = Store.init(allocator);
    global_store = s;

    _ = try s.addStory("Ziex: A full-stack web framework for Zig", null, null, "nurulhudaapon");
    _ = try s.addStory("Show HN: Exact Hacker News Clone in Ziex", null, "I built this clone to show off Ziex.", "nurulhudaapon");
    _ = try s.addStory("Zig 0.15.2 Released", "https://ziglang.org/download/0.15.1/release-notes.html", null, "andrewrk");

    const story1_id = s.stories.items[0].id;
    _ = try s.addComment(story1_id, null, "user1", "This looks amazing!");
    _ = try s.addComment(story1_id, null, "user2", "Zig is the future of web dev.");

    const comment1_id = 4;
    _ = try s.addComment(story1_id, comment1_id, "user3", "I agree!");

    return s;
}
