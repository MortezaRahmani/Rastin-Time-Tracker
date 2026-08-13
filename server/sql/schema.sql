PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS projects (
  sync_id TEXT PRIMARY KEY CHECK (length(sync_id) = 32),
  name TEXT NOT NULL,
  color INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS entries (
  sync_id TEXT PRIMARY KEY CHECK (length(sync_id) = 32),
  project_sync_id TEXT NOT NULL REFERENCES projects(sync_id),
  started_at TEXT NOT NULL,
  ended_at TEXT,
  title TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  pauses_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  CHECK (ended_at IS NULL OR ended_at > started_at)
);

CREATE INDEX IF NOT EXISTS projects_updated_at ON projects(updated_at);
CREATE INDEX IF NOT EXISTS entries_updated_at ON entries(updated_at);
CREATE INDEX IF NOT EXISTS entries_project_started_at
  ON entries(project_sync_id, started_at DESC);
