CREATE TABLE IF NOT EXISTS installations (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'registered',
  oauth_state TEXT,
  oauth_state_expires_at TEXT,
  last_error TEXT,
  last_sync_at TEXT,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS oura_connections (
  install_id TEXT PRIMARY KEY,
  oura_user_id TEXT NOT NULL UNIQUE,
  access_token_encrypted TEXT NOT NULL,
  refresh_token_encrypted TEXT NOT NULL,
  scopes TEXT,
  token_expires_at TEXT,
  connected_at TEXT NOT NULL,
  stale INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (install_id) REFERENCES installations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS oura_daily_scores (
  install_id TEXT NOT NULL,
  day TEXT NOT NULL,
  sleep_score REAL,
  readiness_score REAL,
  activity_score REAL,
  sleep_contributors_json TEXT,
  readiness_contributors_json TEXT,
  activity_contributors_json TEXT,
  sleep_timestamp TEXT,
  readiness_timestamp TEXT,
  activity_timestamp TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (install_id, day),
  FOREIGN KEY (install_id) REFERENCES installations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS oura_webhook_subscriptions (
  id TEXT PRIMARY KEY,
  install_id TEXT,
  event_type TEXT NOT NULL,
  data_type TEXT NOT NULL,
  callback_url TEXT NOT NULL,
  expiration_time TEXT,
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS sync_runs (
  id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  mode TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  records_written INTEGER NOT NULL DEFAULT 0,
  error_summary TEXT,
  FOREIGN KEY (install_id) REFERENCES installations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_scores_install_day ON oura_daily_scores (install_id, day);
CREATE INDEX IF NOT EXISTS idx_connections_user ON oura_connections (oura_user_id);
CREATE INDEX IF NOT EXISTS idx_sync_runs_install ON sync_runs (install_id, started_at);
