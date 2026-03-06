# ── Build stage ───────────────────────────────────────────────────────────────
FROM node:20-alpine

WORKDIR /app

# Install dependencies first (layer-cached)
COPY package.json package-lock.json* ./
RUN npm install --production

# Copy server source
COPY server.js .

# Cloud Run injects PORT — our server already reads process.env.PORT
EXPOSE 8080

CMD ["node", "server.js"]
