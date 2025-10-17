const { Kafka } = require('kafkajs');
const crypto = require('crypto');

let kafkaMessagesProduced, kafkaMessagesConsumed;

try {
  const metrics = require('./metrics');
  kafkaMessagesProduced = metrics.kafkaMessagesProduced;
  kafkaMessagesConsumed = metrics.kafkaMessagesConsumed;
} catch (error) {
  kafkaMessagesProduced = { labels: () => ({ inc: () => {} }) };
  kafkaMessagesConsumed = { labels: () => ({ inc: () => {} }) };
}

const MESSAGE_SECRET = process.env.MESSAGE_SECRET || 'your_secure_message_secret_key_12345';

function signMessage(message) {
  const payload = JSON.stringify({
    event: message.event,
    from: message.from,
    to: message.to,
    orderId: message.orderId,
    timestamp: message.timestamp
  });
  
  const signature = crypto
    .createHmac('sha256', MESSAGE_SECRET)
    .update(payload)
    .digest('hex');
  
  return signature;
}

function verifyMessage(message, signature) {
  const expectedSignature = signMessage(message);
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}

const kafka = new Kafka({
  clientId: `erp-microservice-${process.env.COMPANY}`,
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092']
});

const producer = kafka.producer();
const consumer = kafka.consumer({ 
  groupId: `erp-group-${process.env.COMPANY}`,
  allowAutoTopicCreation: true
});

let isConnected = false;

const connectKafka = async () => {
  if (!isConnected) {
    await producer.connect();
    await consumer.connect();
    isConnected = true;
    console.log(`Kafka connected for company: ${process.env.COMPANY}`);
  }
};

const sendMessage = async (topic, message) => {
  try {
    await connectKafka();
    
    message.sender = process.env.COMPANY;
    
    const signature = signMessage(message);
    message.signature = signature;
    
    const companyTopic = `${topic}.${message.to}`;
    
    await producer.send({
      topic: companyTopic,
      messages: [
        { 
          value: JSON.stringify(message),
          headers: {
            'x-sender': process.env.COMPANY,
            'x-recipient': message.to,
            'x-signature': signature
          }
        }
      ]
    });
    
    kafkaMessagesProduced.labels(companyTopic).inc();
    console.log(`Message sent to topic ${companyTopic}:`, {
      event: message.event,
      from: message.from,
      to: message.to,
      orderId: message.orderId
    });
  } catch (error) {
    console.error('Error sending message to Kafka:', error);
  }
};

const subscribeToTopic = async (topic, callback) => {
  try {
    await connectKafka();
    
    await consumer.subscribe({ 
      topic, 
      fromBeginning: true
    });
    
    console.log(`Subscribed to topic: ${topic}`);
    
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = JSON.parse(message.value.toString());
          
          const headers = message.headers || {};
          const recipient = headers['x-recipient']?.toString();
          const sender = headers['x-sender']?.toString();
          const signature = headers['x-signature']?.toString();
          
          if (recipient !== process.env.COMPANY) {
            console.warn(`Message not for us. Expected: ${process.env.COMPANY}, Got: ${recipient}`);
            return;
          }
          
          if (!signature || !verifyMessage(value, signature)) {
            console.error(`SECURITY ALERT: Invalid signature! Possible tampering detected.`);
            return;
          }
          
          if (sender !== value.from) {
            console.error(`SECURITY ALERT: Sender mismatch! Header: ${sender}, Message: ${value.from}`);
            return;
          }
          
          console.log(`Verified message from topic ${topic}:`, {
            event: value.event,
            from: value.from,
            to: value.to,
            orderId: value.orderId
          });
          
          kafkaMessagesConsumed.labels(topic).inc();
          await callback(value);
        } catch (error) {
          console.error('Error processing Kafka message:', error);
        }
      }
    });
  } catch (error) {
    console.error('Error subscribing to Kafka topic:', error);
  }
};

const subscribeToMultipleTopics = async (handlers) => {
  try {
    await connectKafka();
    
    const topics = Object.keys(handlers);
    
    const subscribeWithRetry = async (topic, retries = 5) => {
      const companyTopic = `${topic}.${process.env.COMPANY}`;
      
      for (let i = 0; i < retries; i++) {
        try {
          await consumer.subscribe({ 
            topic: companyTopic, 
            fromBeginning: false  
          });
          console.log(`Subscribed to topic: ${companyTopic}`);
          return;
        } catch (error) {
          if (i === retries - 1) throw error;
          console.log(`Topic ${companyTopic} not ready, retrying in 2s... (${i + 1}/${retries})`);
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      }
    };
    
    for (const topic of topics) {
      await subscribeWithRetry(topic);
    }
    
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = JSON.parse(message.value.toString());
          
          const headers = message.headers || {};
          const recipient = headers['x-recipient']?.toString();
          const sender = headers['x-sender']?.toString();
          const signature = headers['x-signature']?.toString();
          
          if (recipient !== process.env.COMPANY) {
            console.warn(`Message not for us. Expected: ${process.env.COMPANY}, Got: ${recipient}`);
            return;
          }
          
          if (!signature || !verifyMessage(value, signature)) {
            console.error(`SECURITY ALERT: Invalid signature! Possible tampering detected.`);
            console.error(`   Topic: ${topic}`);
            console.error(`   Claimed sender: ${value.from}`);
            return;
          }
          
          if (sender !== value.from) {
            console.error(`SECURITY ALERT: Sender mismatch!`);
            console.error(`   Header sender: ${sender}`);
            console.error(`   Message sender: ${value.from}`);
            return;
          }
          
          console.log(`Verified message from topic ${topic}:`, {
            event: value.event,
            from: value.from,
            to: value.to,
            orderId: value.orderId
          });
          
          kafkaMessagesConsumed.labels(topic).inc();
          
          const baseTopic = topic.split('.').slice(0, -1).join('.');
          const handler = handlers[baseTopic];
          
          if (handler) {
            await handler(value);
          }
        } catch (error) {
          console.error('Error processing Kafka message:', error);
        }
      }
    });
    
    console.log('Kafka consumer running and listening for messages');
  } catch (error) {
    console.error('Error subscribing to Kafka topics:', error);
  }
};

module.exports = {
  sendMessage,
  subscribeToTopic,
  subscribeToMultipleTopics,
  producer,
  consumer,
  signMessage,
  verifyMessage
};