#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WC_VERSION=`get_config_value 'wc_version' 'latest'`
TJ_GIT_URL=`get_config_value 'tj_git_url' 'https://github.com/taxjar/taxjar-woocommerce-plugin.git'`
TJ_BRANCH=`get_config_value 'tj_branch' 'master'`
INSTALL_WOOCOMMERCE_SUBSCRIPTIONS=`get_config_value 'install_woocommerce_subscriptions' 'false'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}
INITIAL_INSTALL=false

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
INITIAL_INSTALL=true
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Install and configure the requested version of wordpress
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
   echo "Downloading WordPress..."
   cd ${VVV_PATH_TO_SITE}/public_html
   noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
   echo "Configuring WordPress Stable..."
   cd ${VVV_PATH_TO_SITE}/public_html
   noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
fi

# Install and configure the requested version of WooCommerce
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/woocommerce/woocommerce.php" ]]; then
  echo -e "\nInstalling WooCommerce Version '${WC_VERSION}'"
  if [ "${WC_VERSION}" = "latest" ]; then
    noroot wp plugin install woocommerce --force --activate
  else
    noroot wp plugin install woocommerce --force --activate --version="${WC_VERSION}"
  fi
fi

# Install and activate Storefront
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-content/themes/storefront/functions.php" ]]; then
  echo -e "\nInstalling Storefront theme"
  noroot wp theme install storefront
  noroot wp theme activate storefront
fi
  
# Clone, checkout from branch and activate taxjar from requested repo
# Install unit tests
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/taxjar-woocommerce-plugin/taxjar-woocommerce.php" ]]; then
  echo -e "\nInstalling TaxJar From '${TJ_GIT_URL}'"
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins
  git clone ${TJ_GIT_URL}
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/taxjar-woocommerce-plugin
  git checkout ${TJ_BRANCH}
  noroot wp plugin activate taxjar-woocommerce-plugin
  export WP_TESTS_DIR="${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/taxjar-woocommerce-plugin/tmp/wordpress-tests-lib/"
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/taxjar-woocommerce-plugin/tests/bin/
  noroot ./install.sh wordpressone root root
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/taxjar-woocommerce-plugin/
  noroot composer install
fi

# Install WooCommerce Subscriptions
echo -e "\nChecking if woo subscriptions should be installed"
if [ "${INSTALL_WOOCOMMERCE_SUBSCRIPTIONS}" = "true" ]; then
  echo -e "\nAttempting to install WooCommerce Substriptions from local zip file"
  if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/woocommerce-subscriptions/woocommerce-subscriptions.php" ]]; then
    if [[ -f "/vagrant/plugins/woocommerce-subscriptions.zip" ]]; then
      cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins
      noroot wp plugin install /vagrant/plugins/woocommerce-subscriptions.zip
      noroot wp plugin activate woocommerce-subscriptions
    else
      echo -e "\nNo plugin file found in /vagrant/plugins/"
    fi
  else
    echo -e "\nWooCommerce Subscriptions already installed"
  fi
else
  echo -e "\nWoo Subscriptions does not need to be installed"
fi

# Configure WooCommerce by updating DB
if [ "${INITIAL_INSTALL}" = true ]; then

  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins

  if ! $(noroot wp core is-installed); then
    noroot wp core install --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
    
    # Handle activation of plugins if DB only is missing
	noroot wp plugin activate woocommerce
    noroot wp plugin activate --all
    
    # Activate theme when only db is missing
    noroot wp theme activate storefront
    
  fi
  
  noroot wp option update permalink_structure "/%postname%/"
  noroot wp option update woocommmerce_store_address "1 East Main Street"
  noroot wp option update woocommerce_store_city "Payson"
  noroot wp option update woocommerce_default_country "US:UT"
  noroot wp option update woocommerce_store_postcode "84651"
  noroot wp option update woocommerce_currency "USD"
  noroot wp option update woocommerce_cheque_settings '{"enabled": "yes"}' --format=json
  
  CART_PAGE_ID=`noroot wp post create --post_title='Cart' --post_type='page' --post_status='publish' --porcelain`
  CHECKOUT_PAGE_ID=`noroot wp post create --post_title='Checkout' --post_type='page' --post_status='publish' --porcelain`
  ACCOUNT_PAGE_ID=`noroot wp post create --post_title='My account' --post_type='page' --post_status='publish' --porcelain`
  SHOP_PAGE_ID=`noroot wp post create --post_title='Shop' --post_type='page' --post_status='publish' --porcelain`
  
  noroot wp option update woocommerce_cart_page_id "${CART_PAGE_ID}"
  noroot wp option update woocommerce_myaccount_page_id "${CHECKOUT_PAGE_ID}"
  noroot wp option update woocommerce_myaccount_page_id "${ACCOUNT_PAGE_ID}"
  noroot wp option update woocommerce_shop_page_id "${SHOP_PAGE_ID}"
  
  noroot wp wc product create --name='Simple Product' --sku='simple-product' --regular_price=10.00 --user=1
fi

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s##${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi