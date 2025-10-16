const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

const query = (text, params) => pool.query(text, params);

const initDatabase = async () => {
  try {
    await pool.connect();
    console.log(`Connected to database: ${process.env.DB_NAME}`);
  } catch (error) {
    console.error('Database connection error:', error);
    process.exit(1);
  }
};

module.exports = {
  query,
  initDatabase,
  pool
};