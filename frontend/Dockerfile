FROM nginxinc/nginx-unprivileged:1.27-alpine

LABEL org.opencontainers.image.title="skillpulse-frontend" \
      org.opencontainers.image.description="SkillPulse static UI — nginx nonroot" \
      org.opencontainers.image.base.name="nginxinc/nginx-unprivileged:1.27-alpine"

COPY --chown=101:101 nginx.conf  /etc/nginx/conf.d/default.conf
COPY --chown=101:101 index.html  /usr/share/nginx/html/
COPY --chown=101:101 css/        /usr/share/nginx/html/css/
COPY --chown=101:101 js/         /usr/share/nginx/html/js/

USER 101
EXPOSE 8080
ENTRYPOINT ["nginx", "-g", "daemon off;"]
