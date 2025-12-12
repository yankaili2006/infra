ARG GOLANG_VERSION=1.25.4
ARG ALPINE_VERSION=3.22

# Builder stage
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} AS builder

# Proxy configuration for go mod download
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG GOPROXY
ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV NO_PROXY=${NO_PROXY}
ENV GOPROXY=${GOPROXY}
# Disable checksum verification for local development (proxy interference)
ENV GOSUMDB=off

# Cached golang dependencies
WORKDIR /build/shared
COPY ./shared/go.mod ./shared/go.sum ./
RUN go mod download

WORKDIR /build/db
COPY ./db/go.mod ./db/go.sum ./
RUN go mod download

# Copy source code
WORKDIR /build

COPY ./shared/pkg ./shared/pkg

COPY ./db/scripts/migrator.go ./db/scripts/migrator.go
COPY ./db/migrations/ ./db/migrations

WORKDIR /build/db

RUN go build -o ./bin/migrator ./scripts/migrator.go
RUN chmod +x ./bin/migrator

FROM alpine:${ALPINE_VERSION}

COPY --from=builder /build/db/bin/migrator .
COPY --from=builder  /build/db/migrations ./migrations

ENTRYPOINT ["./migrator"]
