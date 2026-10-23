FROM node:22-alpine
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/src ./src
RUN mkdir -p /app/data && chown node:node /app/data
ENV NODE_ENV=production
ENV DB_PATH=/app/data/orvella.db
USER node
EXPOSE 8080
CMD ["node", "src/index.js"]
