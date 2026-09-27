-- Additive v3 migration. Provider credentials are never returned by APIs.
CREATE TABLE provider_credentials (
  tenant_id text NOT NULL,
  application_id text NOT NULL,
  provider text NOT NULL CHECK (provider IN ('github','stripe','feishu','generic-hmac')),
  secret_ciphertext text NOT NULL,
  previous_secret_ciphertext text,
  previous_expires_at timestamptz,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,application_id,provider),
  FOREIGN KEY (tenant_id,application_id) REFERENCES applications(tenant_id,id)
);
ALTER TABLE events ADD COLUMN source text NOT NULL DEFAULT 'application'
  CHECK (source IN ('application','provider'));
ALTER TABLE events ADD COLUMN provider text;
ALTER TABLE events ADD CONSTRAINT events_source_provider_check CHECK (
  (source='application' AND provider IS NULL) OR
  (source='provider' AND provider IN ('github','stripe','feishu','generic-hmac'))
);
INSERT INTO hooklab_schema(version) VALUES (3);
