# Etapa 1: Compilar la aplicación Angular
FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Etapa 2: Servir con Nginx y redirigir /api al backend en Railway
FROM nginx:alpine

# Ruta exacta según angular.json (outputPath: dist/frontend)
COPY --from=build /app/dist/frontend/browser /usr/share/nginx/html

# Configuración SPA de Angular y proxy inverso hacia el backend
RUN mkdir -p /etc/nginx/templates && printf 'server {\n\
    listen ${PORT:-80};\n\
    server_name localhost;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
\n\
    location /api/ {\n\
        proxy_pass https://backend-production-f4f4e2ba.up.railway.app/api/;\n\
        proxy_ssl_server_name on;\n\
        proxy_set_header Host backend-production-f4f4e2ba.up.railway.app;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto $scheme;\n\
    }\n\
\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
}\n' > /etc/nginx/templates/default.conf.template

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
