// Load X-Ray before anything else so it can patch outgoing HTTP/AWS SDK calls.
const AWSXRay = require('aws-xray-sdk');
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { createClient } = require('redis');
const { pool, ensureSchema } = require('./db');

const app = express();
app.use(express.json());
app.use(AWSXRay.express.openSegment('auth-service'));

const PORT = process.env.CONTAINER_PORT || 3000;
const APP_SECRETS = JSON.parse(process.env.APP_SECRETS || '{}');
const JWT_SECRET = APP_SECRETS.jwt_secret || 'dev-only-fallback-secret';

// Shared Redis session cache (ElastiCache) - same instance every stateless
// container connects to, so a session survives which task handles the request.
const redis = createClient({
  socket: { host: process.env.REDIS_HOST, port: Number(process.env.REDIS_PORT) || 6379 },
});
redis.on('error', (err) => console.error('Redis error', err));

// ALB health check target - keep this cheap and dependency-free where possible.
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok', service: 'auth' }));

app.post('/api/auth/register', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });

  try {
    const hash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email',
      [email, hash]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'email already registered' });
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    const user = result.rows[0];
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      return res.status(401).json({ error: 'invalid credentials' });
    }

    const token = jwt.sign({ sub: user.id, email: user.email }, JWT_SECRET, { expiresIn: '1h' });

    // Cache the session so /api/auth/verify is a Redis lookup, not a re-hash.
    await redis.set(`session:${token}`, JSON.stringify({ userId: user.id }), { EX: 3600 });

    res.json({ token });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  }
});

// Called by Orders/Notifications over Cloud Map DNS (auth.ecs-microservices.local)
// to validate a bearer token without every service needing the JWT secret.
app.get('/api/auth/verify', async (req, res) => {
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) return res.status(401).json({ valid: false });

  try {
    const cached = await redis.get(`session:${token}`);
    if (!cached) return res.status(401).json({ valid: false });

    const payload = jwt.verify(token, JWT_SECRET);
    res.json({ valid: true, userId: payload.sub, email: payload.email });
  } catch {
    res.status(401).json({ valid: false });
  }
});

app.use(AWSXRay.express.closeSegment());

async function start() {
  await ensureSchema();
  await redis.connect();
  app.listen(PORT, () => console.log(`auth-service listening on ${PORT}`));
}

start().catch((err) => {
  console.error('Failed to start auth-service', err);
  process.exit(1);
});
