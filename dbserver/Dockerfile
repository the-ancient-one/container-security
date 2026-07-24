# Database Dockerfile 

# avoid using "latest" tag unless needed, as this will create confusion with the running version number 
FROM mariadb:10.11 

LABEL maintainer="RickRoll"
LABEL description="PHP-App Database Docker image"

COPY mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
COPY sqlconfig/csvs23db.sql /docker-entrypoint-initdb.d/csvs23db.sql

EXPOSE 3306