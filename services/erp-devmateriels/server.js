require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { initDatabase } = require('/app/shared/database');
const { subscribeToMultipleTopics, sendMessage } = require('/app/shared/kafka');
const { register, metricsMiddleware } = require('/app/shared/metrics');

const authRoutes = require('./routes/auth');
const orderRoutes = require('./routes/orders');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(metricsMiddleware);

app.use('/api/auth', authRoutes);
app.use('/api/orders', orderRoutes);

app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', service: 'DevMateriels ERP' });
});

app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    res.status(500).end(error);
  }
});

const initializeService = async () => {
  await initDatabase();

  const handlers = {
    'order.request': async (message) => {
      if (message.to === 'DevMateriels') {
        const { query } = require('/app/shared/database');
        
        const existingOrder = await query(
          'SELECT id FROM orders WHERE external_order_id = $1',
          [message.orderId]
        );
        
        if (existingOrder.rows.length > 0) {
          console.log(`Order with external_order_id ${message.orderId} already exists, skipping...`);
          return;
        }
        
        const orderResult = await query(
          `INSERT INTO orders (description, status, client_company, assigned_company, urgency, external_order_id) 
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
          [message.description, 'pending', message.from, 'DevMateriels', message.urgency, message.orderId]
        );

        const order = orderResult.rows[0];

        await query(
          'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
          ['order.request', message, 'in']
        );

        console.log(`Received order request: ${order.id}`);
      }
    },
    
    'order.confirmation': async (message) => {
      if (message.to === 'DevMateriels') {
        const { query } = require('/app/shared/database');
        
        await query(
          'UPDATE orders SET status = $1 WHERE external_order_id = $2',
          ['confirmed', message.orderId]
        );
        
        await query(
          'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
          ['order.confirmation', message, 'in']
        );

        const statusUpdate = {
          event: 'order.status.update',
          from: 'DevMateriels',
          to: message.from,
          orderId: message.orderId,
          status: 'in_progress',
          message: 'Repair work has started',
          timestamp: new Date().toISOString()
        };

        await sendMessage('order.status.update', statusUpdate);
        
        await query(
          'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
          ['order.status.update', statusUpdate, 'out']
        );

        console.log(`Order ${message.orderId} confirmed and work started`);
      }
    }
  };

  await subscribeToMultipleTopics(handlers);

  console.log('DevMateriels ERP service initialized');
};

app.listen(PORT, async () => {
  console.log(`DevMateriels ERP service running on port ${PORT}`);
  await initializeService();
});