const express = require('express');
const { Pool } = require('pg');

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

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    const dbRes = await pool.query('SELECT 1');

    res.json({
      status: 'UP',
      timestamp: new Date().toISOString(),
      services: {
        database: dbRes.rowCount === 1 ? 'healthy' : 'unhealthy'
      }
    });
  } catch (error) {
    res.status(500).json({ status: 'DOWN', error: error.message });
  }
});

// Products API endpoint with direct PostgreSQL query
app.get('/api/products', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT * FROM products ORDER BY id ASC');
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
