require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { initDatabase } = require('../../shared/database');
const { subscribeToTopic, sendMessage } = require('../../shared/kafka');

const authRoutes = require('./routes/auth');
const orderRoutes = require('./routes/orders');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/orders', orderRoutes);

app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', service: 'ConstructWagons ERP' });
});

const initializeService = async () => {
  await initDatabase();
  
  subscribeToTopic('order.quote', async (message) => {
    if (message.to === 'ConstructWagons') {
      const { query } = require('../../shared/database');
      await query(
        'UPDATE orders SET status = $1, estimated_cost = $2, estimated_delivery = $3 WHERE external_order_id = $4',
        ['quoted', message.estimatedCost, message.estimatedDelivery, message.orderId]
      );
      await query(
        'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
        ['order.quote', message, 'in']
      );
    }
  });

  subscribeToTopic('order.status.update', async (message) => {
    if (message.to === 'ConstructWagons') {
      const { query } = require('../../shared/database');
      await query(
        'UPDATE orders SET status = $1 WHERE external_order_id = $2',
        [message.status, message.orderId]
      );
      await query(
        'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
        ['order.status.update', message, 'in']
      );
    }
  });

  console.log('ConstructWagons ERP service initialized');
};

app.listen(PORT, async () => {
  console.log(`ConstructWagons ERP service running on port ${PORT}`);
  await initializeService();
});