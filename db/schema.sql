CREATE TABLE IF NOT EXISTS verified_humans (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255),
  world_nullifier_hash TEXT UNIQUE NOT NULL,
  trust_score INTEGER DEFAULT 0,
  verification_status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS agent_passports (
  id SERIAL PRIMARY KEY,
  passport_id VARCHAR(100) UNIQUE NOT NULL,
  agent_name VARCHAR(255) NOT NULL,
  owner_team VARCHAR(255),
  permissions JSONB,
  trust_score INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id SERIAL PRIMARY KEY,
  event_type VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100),
  entity_id VARCHAR(255),
  details JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
