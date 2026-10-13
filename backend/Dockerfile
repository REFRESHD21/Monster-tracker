FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json server.mjs ./
RUN mkdir /data && chown node:node /data
USER node
ENV MONSTER_DB_PATH=/data/payments.db
EXPOSE 8080
CMD ["node", "server.mjs"]
