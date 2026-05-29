# frontend/end-user-liff/Dockerfile
FROM node:20-alpine AS build
WORKDIR /app

# Declare build args
ARG VITE_LIFF_ID
ARG VITE_BACKEND_URL

# Make them available to Vite during build
ENV VITE_LIFF_ID=$VITE_LIFF_ID
ENV VITE_BACKEND_URL=$VITE_BACKEND_URL

COPY frontend/end-user-liff/package*.json .
RUN npm install

COPY frontend/end-user-liff/. .
RUN npm run build

FROM nginx:alpine AS runtime
COPY --from=build /app/dist /usr/share/nginx/html
COPY frontend/end-user-liff/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]