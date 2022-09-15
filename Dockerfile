# from https://www.drupal.org/docs/system-requirements/php-requirements
FROM php:8.1-apache-buster

# install the PHP extensions we need
RUN set -eux; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libjpeg-dev \
		libldap2-dev \
		libpng-dev \
		libpq-dev \
		libsqlite3-dev \
		libzip-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		gd \
		ldap \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		pdo_sqlite \
		zip \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
	    git \
		unzip \
		zip \
	;

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
# see https://symfony.com/doc/current/performance.html
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

ENV IDENTITY_PROVIDER_VERSION 0.0.30

WORKDIR /opt/drupal
RUN set -eux; \
    export PATH=$PATH":/usr/bin" \
	export COMPOSER_HOME="$(mktemp -d)"; \
	composer create-project --no-interaction "sanduhrs/identity-provider-project:$IDENTITY_PROVIDER_VERSION" ./; \
	mkdir keys; \
	cp web/sites/default/default.settings.php web/sites/default/settings.php; \
	echo "\$databases['default']['default'] = array (\n  'database' => 'sites/default/files/.ht.sqlite',\n  'prefix' => '',\n  'namespace' => 'Drupal\\Core\\Database\\Driver\\sqlite',\n  'driver' => 'sqlite',\n);" >> web/sites/default/settings.php; \
	echo "\$settings['config_sync_directory'] = 'sites/default/files/config_`head -c 500 /dev/urandom | tr -dc 'a-zA-Z0-9~%^&*_-' | fold -w 64 | head -n 1`/sync';" >> web/sites/default/settings.php; \
	cp web/sites/default/default.services.yml web/sites/default/services.yml; \
	chown -R www-data:www-data web/sites web/modules web/themes keys; \
	rmdir /var/www/html; \
	ln -sf /opt/drupal/web /var/www/html; \
	# delete composer cache
	rm -rf "$COMPOSER_HOME"

ENV PATH=${PATH}:/opt/drupal/vendor/bin

# vim:set ft=dockerfile:
