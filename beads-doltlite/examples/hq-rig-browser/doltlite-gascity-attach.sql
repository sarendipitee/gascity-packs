-- HQ + rig database browser queries for /data/projects/doltlite-gascity.
--
-- Open this DB first with the DoltLite-linked browser:
--   /data/projects/doltlite-gascity/.beads/doltlite/hq.db
--
-- Then run this script from DB Browser's Execute SQL tab to attach the rig DBs.
-- For another city, adjust the absolute paths below.

ATTACH DATABASE '/data/projects/doltlite-gascity/beads-doltlite/.beads/doltlite/bd.db' AS rig_bd;
ATTACH DATABASE '/data/projects/doltlite-gascity/gascity/.beads/doltlite/gc.db' AS rig_gc;
ATTACH DATABASE '/data/projects/doltlite-gascity/gascity-packs/.beads/doltlite/gp.db' AS rig_gp;
ATTACH DATABASE '/data/projects/doltlite-gascity/gascity/gascity-dashboard/.beads/doltlite/gd.db' AS rig_gd;
ATTACH DATABASE '/data/projects/doltlite-gascity/lightjj/.beads/doltlite/lj.db' AS rig_lj;

-- Confirm all attached databases.
PRAGMA database_list;

-- Issue/event/comment counts by database.
SELECT 'hq' AS db, 'city' AS scope, COUNT(*) AS issues,
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0) AS open_issues,
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0) AS in_progress_issues,
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0) AS closed_issues
  FROM main.issues
UNION ALL
SELECT 'bd', 'rig:beads-doltlite', COUNT(*),
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0)
  FROM rig_bd.issues
UNION ALL
SELECT 'gc', 'rig:gascity', COUNT(*),
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0)
  FROM rig_gc.issues
UNION ALL
SELECT 'gp', 'rig:gascity-packs', COUNT(*),
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0)
  FROM rig_gp.issues
UNION ALL
SELECT 'gd', 'rig:gascity-dashboard', COUNT(*),
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0)
  FROM rig_gd.issues
UNION ALL
SELECT 'lj', 'rig:lightjj', COUNT(*),
       COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END), 0),
       COALESCE(SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END), 0)
  FROM rig_lj.issues
ORDER BY db;

-- Recent beads across HQ and rigs.
SELECT 'hq' AS db, id, title, status, priority, assignee, owner, rig, updated_at
  FROM main.issues
UNION ALL
SELECT 'bd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_bd.issues
UNION ALL
SELECT 'gc', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gc.issues
UNION ALL
SELECT 'gp', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gp.issues
UNION ALL
SELECT 'gd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gd.issues
UNION ALL
SELECT 'lj', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_lj.issues
ORDER BY updated_at DESC
LIMIT 100;

-- Open or in-progress beads across HQ and rigs.
SELECT 'hq' AS db, id, title, status, priority, assignee, owner, rig, updated_at
  FROM main.issues
 WHERE status IN ('open', 'in_progress')
UNION ALL
SELECT 'bd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_bd.issues
 WHERE status IN ('open', 'in_progress')
UNION ALL
SELECT 'gc', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gc.issues
 WHERE status IN ('open', 'in_progress')
UNION ALL
SELECT 'gp', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gp.issues
 WHERE status IN ('open', 'in_progress')
UNION ALL
SELECT 'gd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gd.issues
 WHERE status IN ('open', 'in_progress')
UNION ALL
SELECT 'lj', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_lj.issues
 WHERE status IN ('open', 'in_progress')
ORDER BY priority ASC, updated_at DESC;

-- Blocked beads across HQ and rigs.
SELECT 'hq' AS db, id, title, status, priority, assignee, owner, rig, updated_at
  FROM main.issues
 WHERE COALESCE(is_blocked, 0) <> 0
UNION ALL
SELECT 'bd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_bd.issues
 WHERE COALESCE(is_blocked, 0) <> 0
UNION ALL
SELECT 'gc', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gc.issues
 WHERE COALESCE(is_blocked, 0) <> 0
UNION ALL
SELECT 'gp', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gp.issues
 WHERE COALESCE(is_blocked, 0) <> 0
UNION ALL
SELECT 'gd', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_gd.issues
 WHERE COALESCE(is_blocked, 0) <> 0
UNION ALL
SELECT 'lj', id, title, status, priority, assignee, owner, rig, updated_at
  FROM rig_lj.issues
 WHERE COALESCE(is_blocked, 0) <> 0
ORDER BY updated_at DESC;

-- Search titles/notes/descriptions across all databases. Edit the pattern.
WITH needle(pattern) AS (VALUES ('%workspace%'))
SELECT 'hq' AS db, id, title, status, priority, updated_at
  FROM main.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
UNION ALL
SELECT 'bd', id, title, status, priority, updated_at
  FROM rig_bd.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
UNION ALL
SELECT 'gc', id, title, status, priority, updated_at
  FROM rig_gc.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
UNION ALL
SELECT 'gp', id, title, status, priority, updated_at
  FROM rig_gp.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
UNION ALL
SELECT 'gd', id, title, status, priority, updated_at
  FROM rig_gd.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
UNION ALL
SELECT 'lj', id, title, status, priority, updated_at
  FROM rig_lj.issues, needle
 WHERE lower(COALESCE(title, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(notes, ''))
       LIKE lower(pattern)
ORDER BY updated_at DESC
LIMIT 100;

-- Label counts by database.
SELECT 'hq' AS db, label, COUNT(*) AS n FROM main.labels GROUP BY label
UNION ALL
SELECT 'bd', label, COUNT(*) FROM rig_bd.labels GROUP BY label
UNION ALL
SELECT 'gc', label, COUNT(*) FROM rig_gc.labels GROUP BY label
UNION ALL
SELECT 'gp', label, COUNT(*) FROM rig_gp.labels GROUP BY label
UNION ALL
SELECT 'gd', label, COUNT(*) FROM rig_gd.labels GROUP BY label
UNION ALL
SELECT 'lj', label, COUNT(*) FROM rig_lj.labels GROUP BY label
ORDER BY db, n DESC, label;

-- Dependency edges across databases.
SELECT 'hq' AS db, issue_id, depends_on_id, type, created_at
  FROM main.dependencies
UNION ALL
SELECT 'bd', issue_id, depends_on_id, type, created_at
  FROM rig_bd.dependencies
UNION ALL
SELECT 'gc', issue_id, depends_on_id, type, created_at
  FROM rig_gc.dependencies
UNION ALL
SELECT 'gp', issue_id, depends_on_id, type, created_at
  FROM rig_gp.dependencies
UNION ALL
SELECT 'gd', issue_id, depends_on_id, type, created_at
  FROM rig_gd.dependencies
UNION ALL
SELECT 'lj', issue_id, depends_on_id, type, created_at
  FROM rig_lj.dependencies
ORDER BY created_at DESC
LIMIT 200;

-- Optional cleanup for this connection.
-- DETACH DATABASE rig_bd;
-- DETACH DATABASE rig_gc;
-- DETACH DATABASE rig_gp;
-- DETACH DATABASE rig_gd;
-- DETACH DATABASE rig_lj;
