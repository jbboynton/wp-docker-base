FROM php:7.4-apache

COPY config/bash_config /tmp/bash_config
COPY config/custom.ini /usr/local/etc/php/conf.d/custom.ini
COPY config/wp-su.sh /usr/local/bin/wp
COPY config/apache-config.conf /etc/apache2/sites-enabled/000-default.conf
COPY config/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Persistent dependencies
RUN set -eux; \
		apt-get update; \
		apt-get install -y --no-install-recommends \
      ghostscript \
    ; \
    rm -rf /var/lib/apt/lists/*

# PHP extensions
RUN set -ex; \
    saved_apt_mark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      libfreetype6-dev \
      libjpeg-dev \
      libmagickwand-dev \
      libpng-dev \
      libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j "$(nproc)" \
      bcmath \
      exif \
      gd \
      mysqli \
      opcache \
      zip \
    ; \
    pecl install imagick-3.4.4; \
    docker-php-ext-enable imagick; \
    # reset apt-mark's "manual" list so that "purge --auto-remove" will remove
    # all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $saved_apt_mark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
      | awk '/=>/ { print $3 }' \
      | sort -u \
      | xargs -r dpkg-query -S \
      | cut -d: -f1 \
      | sort -u \
      | xargs -rt apt-mark manual \
    ; \
    apt-get purge -y --auto-remove \
      -o APT::AutoRemove::RecommendsImportant=false \
    ; \
    apt-get update; \
    apt-get install -y \
      git \
      less \
      make \
      rsync \
      sudo \
      unzip \
      vim \
      zip \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    curl -sS https://getcomposer.org/installer | \
      php -- --install-dir=/usr/local/bin --filename=composer \
    ; \
    curl -o /usr/local/bin/wp-cli.phar \
      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    ; \
    chmod +x /usr/local/bin/wp-cli.phar; \
    chmod +x /usr/local/bin/wp; \
    chmod +x /usr/local/bin/docker-entrypoint.sh; \
    mkdir -p /var/www/app; \
    cat /tmp/bash_config >> /root/.bashrc; \
    rm /tmp/bash_config

# Recommended php.ini settings
# https://secure.php.net/manual/en/opcache.installation.php
RUN { \
      echo 'opcache.memory_consumption=128'; \
      echo 'opcache.interned_strings_buffer=8'; \
      echo 'opcache.max_accelerated_files=4000'; \
      echo 'opcache.revalidate_freq=2'; \
      echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Error reporting
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
RUN { \
      echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
      echo 'display_errors = Off'; \
      echo 'display_startup_errors = Off'; \
      echo 'log_errors = On'; \
      echo 'error_log = /dev/stderr'; \
      echo 'log_errors_max_len = 1024'; \
      echo 'ignore_repeated_errors = On'; \
      echo 'ignore_repeated_source = Off'; \
      echo 'html_errors = Off'; \
    } > /usr/local/etc/php/conf.d/error-logging.ini

# Configure Apache
# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
RUN set -eux; \
    a2enmod rewrite expires; \
    a2enmod remoteip; \
    \
    { \
      echo 'RemoteIPHeader X-Forwarded-For'; \
      echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
      echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
      echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
      echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
      echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    \
    a2enconf remoteip; \
    find /etc/apache2 -type f -name '*.conf' -exec sed -ri \
      's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

WORKDIR /var/www/app

CMD ["docker-entrypoint.sh"]
