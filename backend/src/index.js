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

// ==============================================================================
// FULL CRUD API ENDPOINTS
// ==============================================================================

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
    const { name, price, category } = req.body;
    if (!name || !price || !category) {
      return res.status(400).json({ error: 'Name, price, and category are required' });
    }

    const result = await pool.query(
      'INSERT INTO products (name, price, category) VALUES ($1, $2, $3) RETURNING *',
      [name, price, category]
    );

    res.status(201).json({ message: 'Product created successfully', data: result.rows[0] });
  } catch (error) {
    console.error('Error creating product:', error);
    res.status(500).json({ error: 'Failed to create product', details: error.message });
  }
});

// 3. UPDATE: Modify an existing product
app.put('/api/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, price, category } = req.body;

    const result = await pool.query(
      'UPDATE products SET name = $1, price = $2, category = $3 WHERE id = $4 RETURNING *',
      [name, price, category, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    res.json({ message: 'Product updated successfully', data: result.rows[0] });
  } catch (error) {
    console.error('Error updating product:', error);
    res.status(500).json({ error: 'Failed to update product', details: error.message });
  }
});

// 4. DELETE: Remove a product
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
