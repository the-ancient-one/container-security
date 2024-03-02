# Webserver Dockerfile

# avoid using "latest" tag unless needed, as this will create confusion with the running version number 
FROM rockylinux:9.3

LABEL mantainer="RickRoll"
LABEL description="PHP-App Webserver Docker image"

RUN yum update -y && \
	yum install -y \
	nginx-1:1.20.1-14.el9_2.1 \
	php-8.0.30-1.el9_2 \
	php-mysqlnd-8.0.30-1.el9_2 \
	php-fpm-8.0.30-1.el9_2 && \
	yum clean all && \
	rm -rf /var/cache/yum

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