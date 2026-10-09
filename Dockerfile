# Container for the pdf2music web app: a static bundle served by nginx, which
# also proxies the ONNX weights (see webapp/nginx.conf).

# The bundle is plain JS/wasm and identical on every architecture, so the build
# stage is pinned to the *builder's* platform. Only the tiny nginx runtime layer
# below is arch-specific, which keeps multi-arch builds off QEMU emulation.
FROM --platform=$BUILDPLATFORM node:22-alpine AS build

WORKDIR /app

COPY webapp/package.json webapp/package-lock.json ./
RUN npm ci

COPY webapp/tsconfig.json webapp/vite.config.ts webapp/index.html ./
COPY webapp/src ./src

# Where the browser fetches the model zips from. The default ("/models/") is
# served by the nginx proxy in this image; override it at build time to point at
# your own mirror.
ARG VITE_MODEL_BASE_URL=""
ENV VITE_MODEL_BASE_URL=$VITE_MODEL_BASE_URL
RUN npm run build


FROM nginx:1.27-alpine

COPY webapp/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

# 127.0.0.1 rather than localhost: the latter resolves to ::1 first, and would
# fail on hosts where the container gets no IPv6 loopback.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
