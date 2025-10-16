const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'erp-microservice',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092']
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'erp-group' });

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
    console.log(`Message sent to topic ${topic}:`, message);
  } catch (error) {
    console.error('Error sending message to Kafka:', error);
  }
};

const subscribeToTopic = async (topic, callback) => {
  try {
    await connectKafka();
    await consumer.subscribe({ topic, fromBeginning: true });
    
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = JSON.parse(message.value.toString());
          console.log(`Received message from topic ${topic}:`, value);
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

module.exports = {
  sendMessage,
  subscribeToTopic,
  producer,
  consumer
};