const { Pool } = require('pg');

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
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL,
      item TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ DEFAULT now()
    );
  `);
}

module.exports = { pool, ensureSchema };
