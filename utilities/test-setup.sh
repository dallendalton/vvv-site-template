#!/usr/bin/env bash

SITE=$1
echo $SITE
TJ_PLUGIN_DIR="/srv/www/$SITE/public_html/wp-content/plugins/taxjar-woocommerce-plugin/"
export WP_TESTS_DIR="$TJ_PLUGIN_DIR/tmp/wordpress-tests-lib/"

