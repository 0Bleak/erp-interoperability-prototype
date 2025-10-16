FROM node:18-alpine

WORKDIR /app

COPY services/erp-constructwagons/package.json ./

RUN npm install

COPY services/erp-constructwagons/ ./

COPY shared/ ./shared/

EXPOSE 3000

CMD ["npm", "start"]