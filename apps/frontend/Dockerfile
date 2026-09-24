FROM nginxinc/nginx-unprivileged:1.27-alpine

ARG APP_VERSION=dev

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/

USER root
RUN printf '{"version":"%s"}\n' "${APP_VERSION}" > /usr/share/nginx/html/version.json
# Numeric UID so Kubernetes can verify runAsNonRoot
USER 101

EXPOSE 8080
