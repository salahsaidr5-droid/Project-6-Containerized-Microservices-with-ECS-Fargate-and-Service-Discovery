const AWSXRay = require('aws-xray-sdk');
const express = require('express');
const axios = require('axios');
const { pool, ensureSchema } = require('./db');

const app = express();
app.use(express.json());
app.use(AWSXRay.express.openSegment('orders-service'));

const PORT = process.env.CONTAINER_PORT || 3000;
const NAMESPACE = process.env.CLOUDMAP_NAMESPACE || 'ecs-microservices.local';

// Cloud Map gives every service a stable DNS name inside the namespace -
// no hardcoded IPs, no load balancer needed for internal calls.
const AUTH_URL = `http://auth.${NAMESPACE}:3000`;
const NOTIFICATIONS_URL = `http://notifications.${NAMESPACE}:3000`;

app.get('/health', (_req, res) => res.status(200).json({ status: 'ok', service: 'orders' }));

// Verifies the bearer token by calling Auth service-to-service via Cloud Map DNS.
async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: 'missing Authorization header' });

  try {
    const { data } = await axios.get(`${AUTH_URL}/api/auth/verify`, {
      headers: { Authorization: authHeader },
      timeout: 3000,
    });
    if (!data.valid) return res.status(401).json({ error: 'invalid token' });
    req.userId = data.userId;
    next();
  } catch (err) {
    console.error('auth verify failed', err.message);
    res.status(502).json({ error: 'auth service unavailable' });
  }
}

app.post('/api/orders', requireAuth, async (req, res) => {
  const { item, quantity } = req.body;
  if (!item) return res.status(400).json({ error: 'item required' });

  try {
    const result = await pool.query(
      'INSERT INTO orders (user_id, item, quantity) VALUES ($1, $2, $3) RETURNING *',
      [req.userId, item, quantity || 1]
    );
    const order = result.rows[0];

    // Fire-and-forget: tell Notifications an order was placed. Don't let a
    // notifications hiccup fail the order itself.
    axios
      .post(`${NOTIFICATIONS_URL}/notify`, {
        type: 'order_created',
        userId: req.userId,
        orderId: order.id,
      })
      .catch((err) => console.warn('notification dispatch failed', err.message));

    res.status(201).json(order);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  }
});

app.get('/api/orders', requireAuth, async (req, res) => {
  const result = await pool.query('SELECT * FROM orders WHERE user_id = $1 ORDER BY created_at DESC', [
    req.userId,
  ]);
  res.json(result.rows);
});

app.get('/api/orders/:id', requireAuth, async (req, res) => {
  const result = await pool.query('SELECT * FROM orders WHERE id = $1 AND user_id = $2', [
    req.params.id,
    req.userId,
  ]);
  if (!result.rows[0]) return res.status(404).json({ error: 'not found' });
  res.json(result.rows[0]);
});

app.use(AWSXRay.express.closeSegment());

async function start() {
  await ensureSchema();
  app.listen(PORT, () => console.log(`orders-service listening on ${PORT}`));
}

start().catch((err) => {
  console.error('Failed to start orders-service', err);
  process.exit(1);
});
