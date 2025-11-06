FROM node:18-alpine AS build
WORKDIR /app
COPY . .
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm install && npm run build

FROM node:18-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
RUN npm install -g serve
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
