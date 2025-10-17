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
  res.json({ status: 'OK', service: 'WagonLits ERP' });
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
    'order.quote': async (message) => {
      if (message.to === 'WagonLits') {
        const { query } = require('/app/shared/database');
        await query(
          'UPDATE orders SET status = $1, estimated_cost = $2, estimated_delivery = $3 WHERE id = $4',
          ['quoted', message.estimatedCost, message.estimatedDelivery, message.orderId]
        );
        await query(
          'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
          ['order.quote', message, 'in']
        );
        console.log(`Received quote for order ${message.orderId}`);
      }
    },
    
    'order.status.update': async (message) => {
      if (message.to === 'WagonLits') {
        const { query } = require('/app/shared/database');
        await query(
          'UPDATE orders SET status = $1 WHERE id = $2',
          [message.status, message.orderId]
        );
        await query(
          'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
          ['order.status.update', message, 'in']
        );
        console.log(`Order ${message.orderId} status updated to ${message.status}`);
      }
    }
  };

  await subscribeToMultipleTopics(handlers);

  console.log('WagonLits ERP service initialized');
};

app.listen(PORT, async () => {
  console.log(`WagonLits ERP service running on port ${PORT}`);
  await initializeService();
});