const express = require('express');
const { Pool } = require('pg');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Construct database URL directly from runtime environment variables
const dbUser = process.env.POSTGRES_USER || 'app_user';
const dbPassword = process.env.POSTGRES_PASSWORD || '';
const dbName = process.env.POSTGRES_DB || 'app_db';
const dbHost = process.env.POSTGRES_HOST || 'postgres';

const dbUrl = process.env.DATABASE_URL || `postgres://${dbUser}:${encodeURIComponent(dbPassword)}@${dbHost}:5432/${dbName}`;
const pool = new Pool({ connectionString: dbUrl });

const redisHost = process.env.REDIS_HOST || 'redis';
const redisClient = createClient({ url: `redis://${redisHost}:6379` });

redisClient.on('error', (err) => console.error('Redis Client Error', err));

(async () => {
  try {
    await redisClient.connect();
    console.log('Connected to Redis');
  } catch (err) {
    console.error('Failed to connect to Redis on boot', err);
  }
})();

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    const dbRes = await pool.query('SELECT 1');
    const redisPing = redisClient.isReady ? await redisClient.ping() : 'NOT_CONNECTED';

    res.json({
      status: 'UP',
      timestamp: new Date().toISOString(),
      services: {
        database: dbRes.rowCount === 1 ? 'healthy' : 'unhealthy',
        redis: redisPing === 'PONG' ? 'healthy' : 'unhealthy'
      }
    });
  } catch (error) {
    res.status(500).json({ status: 'DOWN', error: error.message });
  }
});

// Products API endpoint with Redis caching & DB fallback
app.get('/api/products', async (req, res) => {
  try {
    // 1. Check Redis Cache
    if (redisClient.isReady) {
      const cached = await redisClient.get('products_list');
      if (cached) {
        return res.json({ source: 'cache', data: JSON.parse(cached) });
      }
    }

    // 2. Fetch from PostgreSQL
    const { rows } = await pool.query('SELECT * FROM products ORDER BY id ASC');

    // 3. Populate Redis Cache (expire in 60s)
    if (redisClient.isReady && rows.length > 0) {
      await redisClient.setEx('products_list', 60, JSON.stringify(rows));
    }

    res.json({ source: 'database', data: rows });
  } catch (error) {
    console.error('Error fetching products:', error);
    res.status(500).json({ error: 'Failed to retrieve products', details: error.message });
  }
});

// Initial Database Seeding on startup
async function initDb() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        price NUMERIC(10, 2) NOT NULL,
        category VARCHAR(50) NOT NULL
      );
    `);
    
    const countRes = await pool.query('SELECT COUNT(*) FROM products');
    if (parseInt(countRes.rows[0].count, 10) === 0) {
      await pool.query(`
        INSERT INTO products (name, price, category) VALUES
        ('Cloud Developer Laptop', 1499.99, 'Electronics'),
        ('Docker Engineering Hoodie', 59.99, 'Apparel'),
        ('Kubernetes Mechanical Keyboard', 129.50, 'Peripherals'),
        ('DevOps Coffee Mug', 19.99, 'Accessories');
      `);
      console.log('Database seeded with initial products.');
    }
  } catch (err) {
    console.error('Failed to initialize database schema:', err);
  }
}

app.listen(PORT, () => {
  console.log(`Backend API running on port ${PORT}`);
  setTimeout(initDb, 2000);
});
