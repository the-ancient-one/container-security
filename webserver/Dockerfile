# Webserver Dockerfile

FROM rockylinux:9.3

RUN yum update -y && \
	yum install -y \
	nginx \
	php \
	php-mysqlnd \
	php-fpm

COPY webfiles/ /var/www/html

COPY configfiles/nginx.conf     /etc/nginx/nginx.conf
COPY configfiles/php.ini        /etc/php.ini
COPY configfiles/www.conf       /etc/php-fpm.d/www.conf
COPY configfiles/php-fpm.conf   /etc/nginx/conf.d/php-fpm.conf
COPY configfiles/docker-entrypoint.sh /

RUN rm -f /var/www/html/index.html /var/www/html/nginx-logo.png /var/www/html/poweredby.png  && \
	chmod +x /docker-entrypoint.sh && \
    chown nginx:nginx /var/www/html/*.php 


EXPOSE 80 

USER nginx

ENTRYPOINT ["/docker-entrypoint.sh"]
