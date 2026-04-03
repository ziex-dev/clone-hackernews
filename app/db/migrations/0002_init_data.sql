-- Migration number: 0002 	 2026-04-02T19:59:16.901Z
INSERT OR IGNORE INTO stories (id, title, url, text, author, score, comment_count, time)
VALUES
  (1, 'Ziex: A full-stack web framework for Zig', NULL, NULL, 'nurulhudaapon', 1, 3, unixepoch()),
  (2, 'Show HN: Exact Hacker News Clone in Ziex', NULL, 'I built this clone to show off Ziex.', 'nurulhudaapon', 1, 0, unixepoch()),
  (3, 'Zig 0.15.2 Released', 'https://ziglang.org/download/0.15.1/release-notes.html', NULL, 'andrewrk', 1, 0, unixepoch());

INSERT OR IGNORE INTO comments (id, story_id, parent_id, author, text, time, score)
VALUES
  (1, 1, NULL, 'user1', 'This looks amazing!', unixepoch(), 1),
  (2, 1, NULL, 'user2', 'Zig is the future of web dev.', unixepoch(), 1),
  (3, 1, 1, 'user3', 'I agree!', unixepoch(), 1);
