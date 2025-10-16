const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'erp-microservice',
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
    console.log('Kafka connected successfully');
  }
};

const sendMessage = async (topic, message) => {
  try {
    await connectKafka();
    await producer.send({
      topic,
      messages: [
        { value: JSON.stringify(message) }
      ]
    });
    console.log(`✅ Message sent to topic ${topic}:`, message);
  } catch (error) {
    console.error('❌ Error sending message to Kafka:', error);
  }
};

const subscribeToTopic = async (topic, callback) => {
  try {
    await connectKafka();
    
    await consumer.subscribe({ 
      topic, 
      fromBeginning: true
    });
    
    console.log(`✅ Subscribed to topic: ${topic}`);
    
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = JSON.parse(message.value.toString());
          console.log(`📥 Received message from topic ${topic}:`, value);
          await callback(value);
        } catch (error) {
          console.error('❌ Error processing Kafka message:', error);
        }
      }
    });
  } catch (error) {
    console.error('❌ Error subscribing to Kafka topic:', error);
  }
};

const subscribeToMultipleTopics = async (handlers) => {
  try {
    await connectKafka();
    
    const topics = Object.keys(handlers);
    
    // ✅ Subscribe with retry logic
    const subscribeWithRetry = async (topic, retries = 5) => {
      for (let i = 0; i < retries; i++) {
        try {
          await consumer.subscribe({ 
            topic, 
            fromBeginning: false  // ✅ Don't require topic to exist
          });
          console.log(`✅ Subscribed to topic: ${topic}`);
          return;
        } catch (error) {
          if (i === retries - 1) throw error;
          console.log(`⚠️  Topic ${topic} not ready, retrying in 2s... (${i + 1}/${retries})`);
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
          console.log(`📥 Received message from topic ${topic}:`, value);
          
          const handler = handlers[topic];
          if (handler) {
            await handler(value);
          }
        } catch (error) {
          console.error('❌ Error processing Kafka message:', error);
        }
      }
    });
    
    console.log('✅ Kafka consumer running and listening for messages');
  } catch (error) {
    console.error('❌ Error subscribing to Kafka topics:', error);
  }
};

module.exports = {
  sendMessage,
  subscribeToTopic,
  subscribeToMultipleTopics,
  producer,
  consumer
};
