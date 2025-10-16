FROM node:18-alpine

WORKDIR /app

COPY services/erp-devmateriels/package.json ./

RUN npm install

COPY services/erp-devmateriels/ ./

# Copy shared files
COPY shared/ ./shared/

EXPOSE 3000

CMD ["npm", "start"]