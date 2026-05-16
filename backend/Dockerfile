# ── Stage 1: build ──────────────────────────────────────────
FROM golang:1.26-alpine AS builder

WORKDIR /app

# Copy deps first — Docker caches this layer until go.mod/go.sum change
COPY go.mod go.sum ./

RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

# Copy source and build
COPY . .

RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
      -trimpath \
      -ldflags="-w -s -extldflags=-static" \
      -o /skillpulse .

# ── Stage 2: final image ─────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

LABEL org.opencontainers.image.title="skillpulse-backend" \
      org.opencontainers.image.description="SkillPulse Go API — distroless nonroot" \
      org.opencontainers.image.base.name="gcr.io/distroless/static-debian12:nonroot"

COPY --from=builder --chown=nonroot:nonroot --chmod=555 /skillpulse /skillpulse

USER nonroot
EXPOSE 8080
ENTRYPOINT ["/skillpulse"]
