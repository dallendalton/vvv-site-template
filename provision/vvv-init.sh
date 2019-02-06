#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WC_VERSION=`get_config_value 'wc_version' 'latest'`
TJ_GIT_URL=`get_config_value 'tj_git_url' 'https://github.com/taxjar/taxjar-woocommerce-plugin.git'`
TJ_BRANCH=`get_config_value 'tj_branch' 'master'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
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
echo -e "\nInstalling WooCommerce Version '${WC_VERSION}'"
if [ "${WC_VERSION}" = "latest" ]; then
  noroot wp plugin install woocommerce --force --activate
else
  noroot wp plugin install woocommerce --force --activate --version="${WC_VERSION}"
fi
  
# Clone, checkout from branch and activate taxjar from requested repo
echo -e "\nInstalling TaxJar From '${TJ_GIT_URL}'"
cd ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins
git clone ${TJ_GIT_URL}
git checkout ${TJ_BRANCH}
wp plugin activate taxjar

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s##${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"