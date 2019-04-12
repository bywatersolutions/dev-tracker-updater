FROM perl
#FROM tracker-updater

WORKDIR /app

# Copy all files to workdir
COPY . .

RUN cpanm --installdeps . 
RUN cpanm https://github.com/kylemhall/BZ-Client-REST.git

CMD ./tracker-updater.pl
