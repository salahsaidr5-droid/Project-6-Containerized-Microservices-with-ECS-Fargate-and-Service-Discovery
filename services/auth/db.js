const { Pool } = require('pg');

// ECS injects the entire secret JSON string as the env var value when
// "valueFrom" points at the secret ARN without a ::key suffix.
const creds = JSON.parse(process.env.DB_CREDENTIALS || '{}');

const pool = new Pool({
  host: creds.host,
  port: creds.port || 5432,
  user: creds.username,
  password: creds.password,
  database: creds.dbname,
  max: 10,
  idleTimeoutMillis: 30000,
});

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    );
  `);
}

module.exports = { pool, ensureSchema };
