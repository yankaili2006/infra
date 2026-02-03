# Fragments Dockerfile - 优化版本
# Next.js 14 应用，支持开发和生产环境

FROM node:20-alpine AS base

# 安装系统依赖 (单独层，便于缓存)
RUN apk add --no-cache \
    libc6-compat \
    curl \
    bash

# ============================================
# 阶段1: 依赖安装层
# ============================================
FROM base AS deps
WORKDIR /app

# 只复制package文件 (优化缓存)
COPY package.json package-lock.json* ./

# 使用BuildKit缓存加速npm安装
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# ============================================
# 阶段2: 构建层
# ============================================
FROM base AS builder
WORKDIR /app

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json* ./

# 复制源代码
COPY . .

# Set environment variables for build
ENV NEXT_TELEMETRY_DISABLED 1

# 使用BuildKit缓存加速Next.js构建
RUN --mount=type=cache,target=/app/.next/cache \
    npm run build

# ============================================
# 阶段3: 生产运行时层
# ============================================
FROM base AS production
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# 复制public目录
COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Automatically leverage output traces to reduce image size
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3001

ENV PORT 3001
ENV HOSTNAME "0.0.0.0"

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3001/ || exit 1

CMD ["node", "server.js"]

# ============================================
# 阶段4: 开发环境层 (包含所有依赖和源码，支持热重载)
# ============================================
FROM base AS development
WORKDIR /app

ENV NODE_ENV development
ENV NEXT_TELEMETRY_DISABLED 1

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json* ./

# 复制源代码
COPY . .

EXPOSE 3001

ENV PORT 3001
ENV HOSTNAME "0.0.0.0"

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3001/ || exit 1

# 开发模式启动命令 (使用Next.js dev server with turbo)
CMD ["npm", "run", "dev"]
