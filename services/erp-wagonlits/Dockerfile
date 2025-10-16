FROM node:18-alpine

WORKDIR /app

COPY services/erp-wagonlits/package.json ./

RUN npm install

COPY services/erp-wagonlits/ ./

COPY shared/ ./shared/

EXPOSE 3000

CMD ["npm", "start"]