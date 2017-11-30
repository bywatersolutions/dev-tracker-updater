FROM node:8.9.1-stretch

WORKDIR /usr/src/app

# Install app dependencies
COPY package*.json ./

RUN npm install

# Copy all files to workdir
COPY . .

CMD node tracker-updater.js --dev-username $DEV_USERNAME --dev-password $DEV_PASSWORD --community-username $COM_USERNAME --community-password $COM_PASSWORD --rt-username $RT_USERNAME --rt-password $RT_PASSWORD --rt-url $RT_URL --dev-url $DEV_URL --community-url $COM_URL
