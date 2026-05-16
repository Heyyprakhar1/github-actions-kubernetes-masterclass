FROM nginxinc/nginx-unprivileged:1.27-alpine

RUN apk upgrade --no-cache
USER 101

COPY --chown=101:101 nginx.conf  /etc/nginx/conf.d/default.conf
COPY --chown=101:101 index.html  /usr/share/nginx/html/
COPY --chown=101:101 css/        /usr/share/nginx/html/css/
COPY --chown=101:101 js/         /usr/share/nginx/html/js/

EXPOSE 8080
ENTRYPOINT ["nginx", "-g", "daemon off;"]
