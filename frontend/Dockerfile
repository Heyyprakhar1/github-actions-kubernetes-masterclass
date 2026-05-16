# ── Stage 1: prepare static assets ─────────────────────────
FROM alpine:3.20 AS assets
WORKDIR /assets
COPY index.html ./
COPY css ./css
COPY js  ./js

# ── Stage 2: final — Chainguard rootless nginx ──────────────
FROM cgr.dev/chainguard/nginx:latest

LABEL org.opencontainers.image.title="skillpulse-frontend" \
      org.opencontainers.image.description="SkillPulse static UI — Chainguard nginx nonroot" \
      org.opencontainers.image.base.name="cgr.dev/chainguard/nginx:latest" \
      org.opencontainers.image.vendor="SkillPulse"

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=assets --chown=nginx:nginx /assets/index.html /usr/share/nginx/html/
COPY --from=assets --chown=nginx:nginx /assets/css        /usr/share/nginx/html/css
COPY --from=assets --chown=nginx:nginx /assets/js         /usr/share/nginx/html/js

EXPOSE 8080
