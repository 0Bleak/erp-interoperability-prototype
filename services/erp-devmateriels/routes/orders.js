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

router.post('/:id/quote', roleMiddleware(['commercial', 'admin']), async (req, res) => {
  try {
    const { id } = req.params;
    const { estimatedCost, estimatedDelivery } = req.body;

    if (!estimatedCost || !estimatedDelivery) {
      return res.status(400).json({ error: 'Estimated cost and delivery date are required' });
    }

    const orderResult = await query('SELECT * FROM orders WHERE id = $1', [id]);
    
    if (orderResult.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const order = orderResult.rows[0];

    await query(
      'UPDATE orders SET status = $1, estimated_cost = $2, estimated_delivery = $3 WHERE id = $4',
      ['quoted', estimatedCost, estimatedDelivery, id]
    );

    const kafkaMessage = {
      event: 'order.quote',
      from: req.user.company,
      to: order.client_company,
      orderId: parseInt(order.external_order_id) || order.id,  
      estimatedCost: parseFloat(estimatedCost),
      estimatedDelivery: estimatedDelivery,
      timestamp: new Date().toISOString()
    };

    await sendMessage('order.quote', kafkaMessage);

    await query(
      'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
      ['order.quote', kafkaMessage, 'out']
    );

    res.json({ message: 'Quote sent', order: { ...order, status: 'quoted', estimatedCost, estimatedDelivery } });
  } catch (error) {
    console.error('Send quote error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/complete', roleMiddleware(['technician', 'admin']), async (req, res) => {
  try {
    const { id } = req.params;

    const orderResult = await query('SELECT * FROM orders WHERE id = $1', [id]);
    
    if (orderResult.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const order = orderResult.rows[0];

    await query('UPDATE orders SET status = $1 WHERE id = $2', ['completed', id]);

    const kafkaMessage = {
      event: 'order.status.update',
      from: req.user.company,
      to: order.client_company,
      orderId: parseInt(order.external_order_id) || order.id,  
      status: 'completed',
      message: 'Repair work completed',
      timestamp: new Date().toISOString()
    };

    await sendMessage('order.status.update', kafkaMessage);

    await query(
      'INSERT INTO messages (topic, payload, direction) VALUES ($1, $2, $3)',
      ['order.status.update', kafkaMessage, 'out']
    );

    res.json({ message: 'Order completed', order: { ...order, status: 'completed' } });
  } catch (error) {
    console.error('Complete order error:', error);
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
