ARG GOLANG_VERSION=1.25.4

# It has to match with the host OS version (Ubuntu 22.04 = bookworm)
ARG DEBIAN_VERSION=bookworm

FROM golang:${GOLANG_VERSION}-${DEBIAN_VERSION} AS builder

# Set GOPROXY for China network
ENV GOPROXY=https://goproxy.cn,direct
ENV GOSUMDB=off

# Install socat in builder stage
RUN apt-get update && apt-get install -y socat && rm -rf /var/lib/apt/lists/*

# Cached golang dependencies
WORKDIR /build/shared
COPY ./shared/go.mod ./shared/go.sum ./
RUN go mod download

WORKDIR /build/clickhouse
COPY ./clickhouse/go.mod ./clickhouse/go.sum ./
RUN go mod download

WORKDIR /build/orchestrator
COPY ./orchestrator/go.mod ./orchestrator/go.sum ./
RUN go mod download

# Copy source code
WORKDIR /build

COPY ./shared/pkg ./shared/pkg
COPY ./clickhouse/pkg ./clickhouse/pkg

COPY ./orchestrator/internal ./orchestrator/internal
COPY ./orchestrator/cmd ./orchestrator/cmd
COPY ./orchestrator/main.go ./orchestrator/main.go
COPY ./orchestrator/Makefile ./orchestrator/Makefile

WORKDIR /build/orchestrator

ARG COMMIT_SHA
RUN COMMIT_SHA=${COMMIT_SHA:-local-build} CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o bin/orchestrator -ldflags "-X=main.commitSHA=${COMMIT_SHA}" . && COMMIT_SHA=${COMMIT_SHA:-local-build} CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o bin/clean-nfs-cache -ldflags "-X=main.commitSHA=${COMMIT_SHA}" ./cmd/clean-nfs-cache

FROM gcr.io/distroless/base-debian12

# Copy socat and its dependencies from builder
COPY --from=builder /usr/bin/socat /usr/bin/socat
COPY --from=builder /lib/x86_64-linux-gnu/libwrap.so.0 /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libssl.so.3 /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libcrypto.so.3 /lib/x86_64-linux-gnu/

COPY --from=builder /build/orchestrator/bin/clean-nfs-cache .
COPY --from=builder /build/orchestrator/bin/orchestrator .
