# Use the small Alpine variant of the stable Nginx image.
FROM nginx:stable-alpine

# Replace the default page with the lab application.
COPY app/index.html /usr/share/nginx/html/index.html

# Expose a simple endpoint for container and Kubernetes health checks.
COPY app/healthz /usr/share/nginx/html/healthz

# Docker can use this check when the container runs outside Kubernetes.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

EXPOSE 80
