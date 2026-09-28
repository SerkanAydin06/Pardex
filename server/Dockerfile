FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js server_core.js production_server.js social_store.js ./
COPY smoke-test.js ./
COPY *-smoke-test.js ./

# GitHub Actions minutes may be unavailable; production images must still prove
# the complete local WebSocket/session/social/lifecycle suite before release.
RUN npm test

ENV HOST=0.0.0.0
ENV PORT=8765

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1

CMD ["node", "production_server.js"]
