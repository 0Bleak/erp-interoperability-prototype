FROM node:18-alpine

WORKDIR /app

# Copy package.json for this specific service
COPY services/erp-wagonlits/package.json ./

RUN npm install

# Copy the service code
COPY services/erp-wagonlits/ ./

# Copy shared files
COPY shared/ ./shared/

EXPOSE 3000

CMD ["npm", "start"]