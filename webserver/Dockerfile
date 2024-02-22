# Webserver Dockerfile

FROM php:fpm-alpine3.18

RUN apk --no-cache add \
    nginx \
    php81-mysqli

COPY webfiles/ /var/www/html

COPY configfiles/nginx.conf     /etc/nginx/nginx.conf
COPY configfiles/php.ini        /etc/php.ini
COPY configfiles/www.conf       /etc/php-fpm.d/www.conf
COPY configfiles/php-fpm.conf   /etc/nginx/conf.d/php-fpm.conf
COPY configfiles/docker-entrypoint.sh /

RUN rm -f /var/www/html/index.html /var/www/html/nginx-logo.png /var/www/html/poweredby.png  && \
	chmod +x /docker-entrypoint.sh && \
	addgroup apache && adduser -D -G apache -s /bin/sh apache && \
    chown apache:apache /var/www/html/*.php 


EXPOSE 80 

ENTRYPOINT ["/docker-entrypoint.sh"]
