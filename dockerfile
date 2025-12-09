FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

RUN echo 'server { \
  listen 80; \
  location /hostname { \
    return 200 "$hostname"; \
  } \
  location / { \
    root /usr/share/nginx/html; \
    index index.html; \
  } \
}' > /etc/nginx/conf.d/default.conf


