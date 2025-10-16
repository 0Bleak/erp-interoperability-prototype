#!/bin/bash

echo "Fixing all path inconsistencies..."

# Fix erp-wagonlits server.js
cat > services/erp-wagonlits/server.js << 'EOFILE'
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
        'UPDATE orders SET status = $1, estimated_cost = $2, estimated_delivery = $3 WHERE id = $4',
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
        'UPDATE orders SET status = $1 WHERE id = $2',
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
EOFILE

# Fix erp-wagonlits orders.js
cat > services/erp-wagonlits/routes/orders.js << 'EOFILE'
const express = require('express');
const { query } = require('/app/shared/database');
const { authMiddleware, roleMiddleware } = require('/app/shared/auth');
const { sendMessage } = require('/app/shared/kafka');

const router = express.Router();

router.use(authMiddleware);

router.get('/', async (req, res) => {
  try {
    const result = await query(
      'SELECT * FROM orders WHERE client_company = $1 OR assigned_company = $1 ORDER BY created_at DESC',
      [req.user.company]
    );
    res.json({ orders: result.rows });
  } catch (error) {
    console.error('Get orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/', roleMiddleware(['commercial', 'admin']), async (req, res) => {
  try {
    const { description, urgency, assigned_company } = req.body;

    if (!description || !assigned_company) {
      return res.status(400).json({ error: 'Description and assigned company are required' });
    }

    const result = await query(
      `INSERT INTO orders (description, status, client_company, assigned_company, urgency) 
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [description, 'pending', req.user.company, assigned_company, urgency || 'medium']
    );

    const order = result.rows[0];

    const kafkaMessage = {
      event: 'order.request',
      from: req.user.company,
      to: assigned_company,
      orderId: order.id,
      description: order.description,
      urgency: order.urgency,
      timestamp: new Date().toISOString()
    };

    await sendMessage('order.request', kafkaMessage);

    await query(
      'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
      ['order.request', kafkaMessage, 'out']
    );

    res.status(201).json({ order });
  } catch (error) {
    console.error('Create order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/confirm', roleMiddleware(['commercial', 'admin']), async (req, res) => {
  try {
    const { id } = req.params;

    const orderResult = await query('SELECT * FROM orders WHERE id = $1', [id]);
    
    if (orderResult.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const order = orderResult.rows[0];

    await query('UPDATE orders SET status = $1 WHERE id = $2', ['confirmed', id]);

    const kafkaMessage = {
      event: 'order.confirmation',
      from: req.user.company,
      to: order.assigned_company,
      orderId: order.id,
      confirmed: true,
      timestamp: new Date().toISOString()
    };

    await sendMessage('order.confirmation', kafkaMessage);

    await query(
      'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
      ['order.confirmation', kafkaMessage, 'out']
    );

    res.json({ message: 'Order confirmed', order: { ...order, status: 'confirmed' } });
  } catch (error) {
    console.error('Confirm order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      'SELECT * FROM orders WHERE id = $1 AND (client_company = $2 OR assigned_company = $2)',
      [id, req.user.company]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    res.json({ order: result.rows[0] });
  } catch (error) {
    console.error('Get order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
EOFILE

# Fix erp-constructwagons server.js
cat > services/erp-constructwagons/server.js << 'EOFILE'
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
  res.json({ status: 'OK', service: 'ConstructWagons ERP' });
});

const initializeService = async () => {
  await initDatabase();
  
  subscribeToTopic('order.quote', async (message) => {
    if (message.to === 'ConstructWagons') {
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
    if (message.to === 'ConstructWagons') {
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

  console.log('ConstructWagons ERP service initialized');
};

app.listen(PORT, async () => {
  console.log(`ConstructWagons ERP service running on port ${PORT}`);
  await initializeService();
});
EOFILE

echo "✅ All paths fixed!"
echo "Now run: docker-compose down -v && docker-compose build --no-cache && docker-compose up -d"
