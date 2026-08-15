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

// CRUD API ENDPOINTS

// 1. READ: Get all products
app.get('/api/products', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT * FROM products ORDER BY id ASC');
    res.json({ source: 'database', data: rows });
  } catch (error) {
    console.error('Error fetching products:', error);
    res.status(500).json({ error: 'Failed to retrieve products', details: error.message });
  }
});

// 2. CREATE: Add a new product
app.post('/api/products', async (req, res) => {
  try {
    const { name, price, category, image_url } = req.body;
    if (!name || !price || !category) {
      return res.status(400).json({ error: 'Name, price, and category are required' });
    }

    const defaultImg = image_url || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=500&auto=format&fit=crop&q=80';

    const result = await pool.query(
      'INSERT INTO products (name, price, category, image_url) VALUES ($1, $2, $3, $4) RETURNING *',
      [name, price, category, defaultImg]
    );

    res.status(201).json({ message: 'Product created successfully', data: result.rows[0] });
  } catch (error) {
    console.error('Error creating product:', error);
    res.status(500).json({ error: 'Failed to create product', details: error.message });
  }
});

// 3. DELETE: Remove a product
app.delete('/api/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM products WHERE id = $1 RETURNING *', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    res.json({ message: 'Product deleted successfully', data: result.rows[0] });
  } catch (error) {
    console.error('Error deleting product:', error);
    res.status(500).json({ error: 'Failed to delete product', details: error.message });
  }
});

// Initial Database Seeding with Real Product Images
async function initDb() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        price NUMERIC(10, 2) NOT NULL,
        category VARCHAR(50) NOT NULL,
        image_url TEXT
      );
    `);

    // Ensure image_url column exists if table was previously created
    await pool.query(`ALTER TABLE products ADD COLUMN IF NOT EXISTS image_url TEXT;`);

    const countRes = await pool.query('SELECT COUNT(*) FROM products');
    if (parseInt(countRes.rows[0].count, 10) === 0) {
      await pool.query(`
        INSERT INTO products (name, price, category, image_url) VALUES
        ('Wireless Noise-Canceling Headphones', 249.99, 'Electronics', 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500&auto=format&fit=crop&q=80'),
        ('Minimalist Quartz Smartwatch', 179.50, 'Accessories', 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=500&auto=format&fit=crop&q=80'),
        ('Ergonomic Wireless Mechanical Keyboard', 129.99, 'Peripherals', 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=500&auto=format&fit=crop&q=80'),
        ('Premium Leather Everyday Backpack', 89.95, 'Fashion', 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=500&auto=format&fit=crop&q=80');
      `);
      console.log('Database seeded with initial store products & Unsplash images.');
    }
  } catch (err) {
    console.error('Failed to initialize database schema:', err);
  }
}

app.listen(PORT, () => {
  console.log(`Backend API running on port ${PORT}`);
  setTimeout(initDb, 2000);
});
