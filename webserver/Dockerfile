# Webserver Dockerfile

# avoid using "latest" tag unless needed, as this will create confusion with the running version number 
FROM rockylinux:9.3

LABEL maintainer="RickRoll"
LABEL description="PHP-App Webserver Docker image"

# Install Nginx and PHP and clean up to reduce the image size
RUN dnf update -y && \
    dnf install -y \
    nginx \
    php-fpm \
    php-mysqlnd \
    php-gd \
    php-curl && \
    dnf clean all && \
    rm -rf /var/cache/dnf

COPY webfiles/ /var/www/html

COPY configfiles/nginx.conf     /etc/nginx/nginx.conf
COPY configfiles/php.ini        /etc/php.ini
COPY configfiles/www.conf       /etc/php-fpm.d/www.conf
COPY configfiles/php-fpm.conf   /etc/nginx/conf.d/php-fpm.conf
COPY configfiles/docker-entrypoint.sh /

RUN rm -f /var/www/html/index.html /var/www/html/nginx-logo.png /var/www/html/poweredby.png  && \
	chmod +x /docker-entrypoint.sh && \
    chown nginx:nginx /var/www/html/*.php && \
	ln -sf /dev/stdout /var/log/nginx/access.log && \
	ln -sf /dev/stderr /var/log/nginx/error.log 


EXPOSE 80 

ENTRYPOINT ["/docker-entrypoint.sh"]