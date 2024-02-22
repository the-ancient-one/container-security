# Webserver Dockerfile

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y \
    nginx \
    php8.2 \
    php8.2-mysqlnd \
    php8.2-fpm

COPY webfiles/ /var/www/html

COPY configfiles/nginx.conf     /etc/nginx/nginx.conf
COPY configfiles/php.ini        /etc/php.ini
COPY configfiles/www.conf       /etc/php-fpm.d/www.conf
COPY configfiles/php-fpm.conf   /etc/nginx/conf.d/php-fpm.conf
COPY configfiles/docker-entrypoint.sh /

RUN rm -f /var/www/html/index.html /var/www/html/nginx-logo.png /var/www/html/poweredby.png  && \
	chmod +x /docker-entrypoint.sh && \
	addgroup nginx && adduser --system --no-create-home --ingroup nginx --shell /bin/sh nginx && \
    chown nginx:nginx /var/www/html/*.php 


EXPOSE 80 

ENTRYPOINT ["/docker-entrypoint.sh"]
