dbUser=${1:-root}
dbPass=${2:-bamsepuck}
adminUser=${3:-siteadmin}
adminPass=${4:-password}
adminEmail=${5:-webmaster@localhost.test}

themeName=${PWD##*/}
siteName="$(tr '[:lower:]' '[:upper:]' <<< ${themeName:0:1})${themeName:1}"
dbName="wp_$themeName"
dbPrefix="wp_"
siteUrl="http://$themeName.test"

echo "Installing $site..."

###########
# Setup GIT
if ! [ -d .git ]; then
	echo "Initializing GIT"

	git init
fi

###########
# Gitignore
if ! [ -f .gitignore ]; then
	echo "Creating .gitignore"

	cat > .gitignore << EOL
# Ignore garbage
.DS_Store
Thumbs.db
*.sql

# Ignore everything in root
/*

# Except for these files
!.git # TODO: needed?
!.gitignore
!.gitmodules
!README.md

# Include wp-content
!wp-content

# Ignore everything in wp-content
wp-content/*

# Except for
!wp-content/themes/
!wp-content/plugins/

# Ignore all themes
wp-content/themes/*

# Except for
!wp-content/themes/sleek/

# Ignore all plugins
wp-content/plugins/*

# Except for
# !wp-content/plugins/sleek/
EOL
fi

##########
# Htaccess
if ! [ -f .htaccess ]; then
	echo "Creating .htaccess"

	cat > .htaccess << EOL
php_value upload_max_filesize 64M
php_value post_max_size 64M

<IfModule mod_rewrite.c>
	RewriteEngine On
	RewriteBase /

	RewriteRule ^index.php\$ - [L]
	RewriteCond %{REQUEST_FILENAME} !-f
	RewriteCond %{REQUEST_FILENAME} !-d
	RewriteRule . /index.php [L]
</IfModule>
EOL
fi

#########################
# If sleek already exists
if [ -d wp-content/themes/sleek ]; then
	# Make sure vendor is installed before we continue
	if [ -f wp-content/themes/sleek/composer.json ] && [ ! -d wp-content/themes/sleek/vendor ]; then
		echo "Running Composer install"

		cd wp-content/themes/sleek

		composer install

		cd -
	fi
fi

###########
# WordPress
if ! [ -d wp-admin/ ]; then
	wp core download --skip-content
fi

###########
# WP Config
if ! [ -f wp-config.php ]; then
	echo "Creating wp-config.php"

	wp config create --dbname=$dbName --dbprefix=$dbPrefix --dbuser=$dbUser --dbpass=$dbPass --dbhost=localhost --quiet
	wp config set WP_DEBUG true --raw --type=constant
fi

#################
# Create database
mysql -u$dbUser -p$dbPass -e "CREATE DATABASE IF NOT EXISTS ${dbName}"

# We have an existing DB dump
if [ -f db.sql ]; then
	echo "Importing existing database"

	# Drop previous DB
	mysql -u$dbUser -p$dbPass -e "DROP DATABASE ${dbName}"
	mysql -u$dbUser -p$dbPass -e "CREATE DATABASE ${dbName}"

	# Import new
	mysql -u$dbUser -p$dbPass $dbName < db.sql

	# Check DB prefix
	dbPrefix=$(mysql $dbName -u$dbUser -p$dbPass -sse "SELECT DISTINCT SUBSTRING(TABLE_NAME FROM 1 FOR (LENGTH(TABLE_NAME) - 8)) FROM information_schema.TABLES WHERE TABLE_NAME LIKE '%postmeta'")

	# Custom DB prefix
	if ! [ $dbPrefix = "wp_" ]; then
		echo "Changing DB prefix to $dbPrefix"

		wp config set table_prefix $dbPrefix
	fi

	# Rewrite site_url if needed
	# TODO: Should rewrite https://www.siteurl.com, https://siteurl.com, http://www.siteurl.com and http://siteurl.com just to be sure
	currSiteUrl=$(mysql $dbName -u$dbUser -p$dbPass -sse "SELECT option_value FROM ${dbPrefix}options WHERE option_name = 'siteurl'")

	if ! [ $currSiteUrl = $siteUrl ]; then
		echo "Rewriting siteurl from $currSiteUrl to $siteUrl"

		wp search-replace $currSiteUrl $siteUrl

		# Route wp-content to live site
		cat > .htaccess << EOL
php_value upload_max_filesize 64M
php_value post_max_size 64M

<IfModule mod_rewrite.c>
	RewriteEngine On
	RewriteBase /

	# Route wp-content to live site
	RewriteCond %{REQUEST_URI} ^/wp-content/uploads/[^\/]*/.*\$
	RewriteRule ^(.*)\$ $currSiteUrl/\$1 [QSA,L]

	RewriteRule ^index.php\$ - [L]
	RewriteCond %{REQUEST_FILENAME} !-f
	RewriteCond %{REQUEST_FILENAME} !-d
	RewriteRule . /index.php [L]
</IfModule>
EOL
	fi
# No dump, fresh install
else
	echo "Doing fresh install"

	frontpageTitle="Välkommen till förstasidan!"
	blogTitle="Blogg"
	blogDescription="Välkommen till Bloggen!"
	blogUrl="blogg"

	wp core install --url=$siteUrl --title=$siteName --admin_user=$adminUser --admin_password=$adminPass --admin_email=$adminEmail --skip-email

	# Create start and blog page
	wp post update 2 --post_title=Start --post_name=start --post_content="$frontpageTitle" # NOTE: Risky to hard-code 2?? It's the default "Sample page" created by a fresh install...
	blogId=$(wp post create --post_type=page --post_status=publish --post_author=1 --post_name="$blogUrl" --post_title="$blogTitle" --post_content="$blogDescription" --porcelain)

	# Use static front page
	wp option update show_on_front 'page'
	wp option update page_on_front 2 # NOTE: Hard-coded 2 again
	wp option update page_for_posts $blogId

	# Update permalink structure
	wp option update permalink_structure "/$blogUrl/%postname%/"

	# Disable comments
	wp option update default_comment_status closed

	# Time/date formats (TODO: hard-coded...)
	wp option update date_format "j F, Y"
	wp option update time_format "H:i"
fi

###############
# Install sv_SE
# TODO hardcoded
wp language core install sv_SE
wp site switch-language sv_SE

############
# WP Content
if ! [ -d wp-content/ ]; then
	echo "Creating wp-content/"

	mkdir wp-content/
fi

# Plugins
if ! [ -d wp-content/plugins/ ]; then
	echo "Creating wp-content/plugins/"

	mkdir wp-content/plugins/
fi

# Themes
if ! [ -d wp-content/themes/ ]; then
	echo "Creating wp-content/themes/"

	mkdir wp-content/themes/
fi

# Uploads
if ! [ -d wp-content/uploads/ ]; then
	echo "Creating wp-content/uploads/"

	mkdir wp-content/uploads/
fi

chmod 777 wp-content/uploads/

######################
# Sleek does not exist
if ! [ -d wp-content/themes/sleek/ ]; then
	echo "Installing Sleek"

	wp theme install https://github.com/powerbuoy/sleek/archive/master.zip

	# Move into sleek folder
	cd wp-content/themes/sleek

	echo "Running Composer install"

	# Make sure vendor/ exists before we ...
	composer install

	# Active the theme
	wp theme activate sleek

	# Move back
	cd -
fi

#############
# NPM install
if [ -f wp-content/themes/sleek/package.json ] && [ ! -d wp-content/themes/sleek/node_modules ]; then
	cd wp-content/themes/sleek

	echo "Running NPM install"

	npm install

	cd -
fi

# Build
if [ -f wp-content/themes/sleek/webpack.config.js ]; then
	cd wp-content/themes/sleek

	echo "Webpack build"

	npm run build

	cd -
fi

# Build
if [ -f wp-content/themes/sleek/gulpfile.js ]; then
	cd wp-content/themes/sleek

	echo "Gulp build"

	gulp

	cd -
fi

echo "All done! $siteUrl"
