FROM perl

WORKDIR /app

# Copy all files to workdir
COPY . .

RUN cpanm --installdeps . 
RUN cpanm https://github.com/kylemhall/BZ-Client-REST.git

CMD ./tracker-updater.pl --dev-username $DEV_USERNAME --dev-password $DEV_PASSWORD --community-username $COM_USERNAME --community-password $COM_PASSWORD --rt-username $RT_USERNAME --rt-password $RT_PASSWORD --rt-url $RT_URL --dev-url $DEV_URL --community-url $COM_URL

