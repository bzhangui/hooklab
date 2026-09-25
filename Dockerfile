FROM node:24-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="/root/.moon/bin:${PATH}"
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash

WORKDIR /src
COPY moon.mod README.md LICENSE package.json package-lock.json ./
COPY hooklab ./hooklab
COPY cmd ./cmd
COPY platform ./platform
RUN npm ci --ignore-scripts && moon build --target js --deny-warn

FROM node:24-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=build /src/_build/js/debug/build/cmd/hooklab/hooklab.js ./hooklab.js
COPY --from=build /src/platform ./platform
USER node
EXPOSE 8787
CMD ["node", "hooklab.js", "serve-platform", "8787"]
