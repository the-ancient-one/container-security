#!/bin/sh

mkdir -p /run/php-fpm/
/usr/sbin/nginx
/usr/local/sbin/php-fpm -F
# /usr/sbin/sshd -D
