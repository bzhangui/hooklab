-- HookLab platform schema v1. Run only against a dedicated PostgreSQL database.
CREATE TABLE IF NOT EXISTS hooklab_schema (version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
INSERT INTO hooklab_schema(version) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS tenants (
  id text PRIMARY KEY,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS access_keys (
  id uuid PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES tenants(id),
  role text NOT NULL CHECK (role IN ('owner','developer','viewer')),
  token_hash text NOT NULL UNIQUE,
  label text NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS applications (
  tenant_id text NOT NULL REFERENCES tenants(id),
  id text NOT NULL,
  token_hash text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id)
);
CREATE TABLE IF NOT EXISTS endpoints (
  tenant_id text NOT NULL REFERENCES tenants(id),
  id text NOT NULL,
  url text NOT NULL,
  secret_ciphertext text NOT NULL,
  key_id text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id)
);
CREATE TABLE IF NOT EXISTS subscriptions (
  tenant_id text NOT NULL REFERENCES tenants(id),
  id text NOT NULL,
  application_id text NOT NULL,
  endpoint_id text NOT NULL,
  event_types jsonb NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,application_id) REFERENCES applications(tenant_id,id),
  FOREIGN KEY (tenant_id,endpoint_id) REFERENCES endpoints(tenant_id,id)
);
CREATE TABLE IF NOT EXISTS event_contracts (
  tenant_id text NOT NULL,
  application_id text NOT NULL,
  event_type text NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  schema_json jsonb NOT NULL,
  require_cloudevents boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,application_id,event_type,version),
  FOREIGN KEY (tenant_id,application_id) REFERENCES applications(tenant_id,id)
);
CREATE TABLE IF NOT EXISTS events (
  id uuid PRIMARY KEY,
  tenant_id text NOT NULL,
  application_id text NOT NULL,
  event_type text NOT NULL,
  idempotency_key text NOT NULL,
  fingerprint text NOT NULL,
  body text NOT NULL,
  content_type text NOT NULL DEFAULT 'application/json',
  trace_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id,application_id,idempotency_key),
  UNIQUE (tenant_id,id),
  FOREIGN KEY (tenant_id,application_id) REFERENCES applications(tenant_id,id)
);
CREATE INDEX IF NOT EXISTS events_tenant_created_idx ON events(tenant_id,created_at DESC);
CREATE TABLE IF NOT EXISTS deliveries (
  id uuid PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES tenants(id),
  event_id uuid NOT NULL,
  subscription_id text NOT NULL,
  endpoint_id text NOT NULL,
  target_url text NOT NULL,
  secret_ciphertext text NOT NULL,
  key_id text NOT NULL,
  state text NOT NULL CHECK (state IN ('pending','scheduled','in_flight','delivered','dead_lettered')),
  attempt integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_token uuid,
  worker_id text,
  leased_until timestamptz,
  last_status integer,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(event_id,subscription_id),
  FOREIGN KEY (tenant_id,event_id) REFERENCES events(tenant_id,id)
);
CREATE INDEX IF NOT EXISTS deliveries_due_idx ON deliveries(next_attempt_at,created_at) WHERE state IN ('pending','scheduled');
CREATE INDEX IF NOT EXISTS deliveries_lease_idx ON deliveries(leased_until) WHERE state='in_flight';
CREATE INDEX IF NOT EXISTS deliveries_tenant_created_idx ON deliveries(tenant_id,created_at DESC);
CREATE TABLE IF NOT EXISTS delivery_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES tenants(id),
  delivery_id uuid NOT NULL REFERENCES deliveries(id),
  attempt integer NOT NULL,
  status integer,
  outcome text NOT NULL,
  duration_ms integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS attempts_created_idx ON delivery_attempts(created_at DESC);
CREATE INDEX IF NOT EXISTS attempts_delivery_idx ON delivery_attempts(delivery_id,id DESC);
CREATE TABLE IF NOT EXISTS audit_entries (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES tenants(id),
  actor text NOT NULL,
  action text NOT NULL,
  resource text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_tenant_idx ON audit_entries(tenant_id,id DESC);
CREATE TABLE IF NOT EXISTS alerts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES tenants(id),
  kind text NOT NULL,
  state text NOT NULL CHECK (state IN ('open','resolved')),
  message text NOT NULL,
  opened_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS alerts_open_idx ON alerts(tenant_id,kind) WHERE state='open';
