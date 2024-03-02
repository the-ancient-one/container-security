# Database Dockerfile 

# avoid using "latest" tag unless needed, as this will create confusion with the running version number 
FROM mariadb:10.11 

LABEL mantainer="RickRoll"
LABEL description="PHP-App Database Docker image"

COPY mysqld.cnf  /mysql/mysql.conf.d/mysqld.cnf

EXPOSE 3306