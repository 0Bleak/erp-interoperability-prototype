require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { initDatabase } = require('/app/shared/database');
const { subscribeToTopic, sendMessage } = require('/app/shared/kafka');

const authRoutes = require('./routes/auth');
const orderRoutes = require('./routes/orders');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/orders', orderRoutes);

app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', service: 'WagonLits ERP' });
});

const initializeService = async () => {
  await initDatabase();
  
  subscribeToTopic('order.quote', async (message) => {
    if (message.to === 'WagonLits') {
      const { query } = require('/app/shared/database');
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
    if (message.to === 'WagonLits') {
      const { query } = require('/app/shared/database');
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

  console.log('WagonLits ERP service initialized');
};

app.listen(PORT, async () => {
  console.log(`WagonLits ERP service running on port ${PORT}`);
  await initializeService();
});