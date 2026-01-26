# Simple Dockerfile for local development
FROM node:18
WORKDIR /app
COPY . .
RUN yarn install || npm install
EXPOSE 3000
CMD ["yarn", "dev"]
