-- Additive PostgreSQL schema v2. Apply under HookLab's advisory startup lock.
CREATE INDEX IF NOT EXISTS events_retention_idx ON events(tenant_id,created_at,id);
INSERT INTO hooklab_schema(version) VALUES (2);
