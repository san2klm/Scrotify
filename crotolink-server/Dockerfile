FROM node:24-alpine

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src

# /data guarda crotolink.db (ajustes y admin). Montar un volumen para persistir.
RUN mkdir -p /data && chown node:node /data
VOLUME /data

ENV NODE_ENV=production
ENV PORT=8080
ENV DATA_DIR=/data
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1

USER node
CMD ["node", "src/server.js"]
