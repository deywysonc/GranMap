FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY security_headers.conf /etc/nginx/granmap_security_headers.conf
EXPOSE 8080
