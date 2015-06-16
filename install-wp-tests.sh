#!/usr/bin/env bash

# usage: $ install-wp-tests.sh [wp-version] [db-host] [web-port]

WP_VERSION=${1-latest}

DB_HOST=${2-localhost}

# This is used for php built in web server
WP_PORT=${3-8080}

# Theres two wordpress installations
DB_USER='root'
DB_PASS=''
DB_HOST='localhost'

# For unit testing
UNIT_DB_NAME='wp_unit_test'

# For integration testing
WP_DB_NAME='wp_integration'


WP_URL=http://localhost:$WP_PORT

WP_TESTS_DIR=${WP_TESTS_DIR-/tmp/wordpress-tests-lib/includes}
WP_CORE_DIR=${WP_CORE_DIR-/tmp/wordpress/}

set -ex

download() {
  if [ `which curl` ]; then
    curl -s "$1" > "$2";
  elif [ `which wget` ]; then
    wget -nv -O "$2" "$1"
  fi
}

install_wp() {
  if [ -d $WP_CORE_DIR ]; then
    return;
  fi

  mkdir -p $WP_CORE_DIR

  if [ $WP_VERSION == 'latest' ]; then
    local ARCHIVE_NAME='latest'
  else
    local ARCHIVE_NAME="wordpress-$WP_VERSION"
  fi

  download https://wordpress.org/${ARCHIVE_NAME}.tar.gz  /tmp/wordpress.tar.gz
  tar --strip-components=1 -zxmf /tmp/wordpress.tar.gz -C $WP_CORE_DIR

  download https://raw.github.com/markoheijnen/wp-mysqli/master/db.php $WP_CORE_DIR/wp-content/db.php
}

install_test_suite() {
  # portable in-place argument for both GNU sed and Mac OSX sed
  if [[ $(uname -s) == 'Darwin' ]]; then
    local ioption='-i .bak'
  else
    local ioption='-i'
  fi

  # set up testing suite if it doesn't yet exist
  if [ ! "$(ls -A $WP_TESTS_DIR)" ]; then
    # set up testing suite
    mkdir -p $WP_TESTS_DIR
    svn co --quiet http://develop.svn.wordpress.org/trunk/tests/phpunit/includes/ $WP_TESTS_DIR
  fi

  cd $WP_TESTS_DIR

  # Install barebone wp-tests-config.php which is faster for unit tests
  if [ ! -f wp-tests-config.php ]; then
    download https://develop.svn.wordpress.org/trunk/wp-tests-config-sample.php $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
    sed $ioption "s:dirname( __FILE__ ) . '/src/':'$WP_CORE_DIR':" $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
    sed $ioption "s/youremptytestdbnamehere/$UNIT_DB_NAME/" $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
    sed $ioption "s/yourusernamehere/$DB_USER/" $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
    sed $ioption "s/yourpasswordhere/$DB_PASS/" $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
    sed $ioption "s|localhost|${DB_HOST}|" $(dirname ${WP_TESTS_DIR})/wp-tests-config.php
  fi

  # Install real wp-config.php too
  cd $WP_CORE_DIR

  if [ ! -f wp-config.php ]; then
    mv wp-config-sample.php wp-config.php
    sed $ioption "s/database_name_here/$WP_DB_NAME/" $WP_CORE_DIR/wp-config.php
    sed $ioption "s/username_here/$DB_USER/" $WP_CORE_DIR/wp-config.php
    sed $ioption "s/password_here/$DB_PASS/" $WP_CORE_DIR/wp-config.php
    sed $ioption "s|localhost|${DB_HOST}|" $WP_CORE_DIR/wp-config.php
  fi
}

install_db() {
  local DB_NAME=$1
  # parse DB_HOST for port or socket references
  local PARTS=(${DB_HOST//\:/ })
  local DB_HOSTNAME=${PARTS[0]};
  local DB_SOCK_OR_PORT=${PARTS[1]};
  local EXTRA=""

  if ! [ -z $DB_HOSTNAME ] ; then
    if [ $(echo $DB_SOCK_OR_PORT | grep -e '^[0-9]\{1,\}$') ]; then
      EXTRA="--host=$DB_HOSTNAME --port=$DB_SOCK_OR_PORT --protocol=tcp"
    elif ! [ -z $DB_SOCK_OR_PORT ] ; then
      EXTRA="--socket=$DB_SOCK_OR_PORT"
    elif ! [ -z $DB_HOSTNAME ] ; then
      EXTRA="--host=$DB_HOSTNAME --protocol=tcp"
    fi
  fi

  # create database
  mysqladmin create $DB_NAME --user="$DB_USER" --password="$DB_PASS" $EXTRA
}

install_real_wp() {
  # debug
  cd $WP_CORE_DIR
  cat wp-config.php
  ls -lah
  # Install databases with wp-cli
  download https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar wp-cli.phar
  php wp-cli.phar core install  --url=$WP_URL --title='Test' --admin_user='test' --admin_password='test' --admin_email='test@wordpress.dev' --path=$WP_CORE_DIR
}

start_server() {
  cd $WP_CORE_DIR

  # Download router for built-in php server
  download https://raw.githubusercontent.com/Koodimonni/wordpress-test-template/master/router.php router.php

  # Start it in background
  php -S 0.0.0.0:$WP_PORT router.php &
}

install_wp
install_test_suite

# Install db for unit tests
install_db $UNIT_DB_NAME

# Install db for integration tests
install_db $WP_DB_NAME
install_real_wp
start_server
