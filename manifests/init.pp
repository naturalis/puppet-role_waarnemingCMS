# == Class: role_waarnemingCMS
#
# This role creates the necessary configuration for the support.observation.org webservice.
#
class role_waarnemingcms (
  $mysql_root_password = 'password',
  $mysql_override_options = {
  },
  $dbuser = 'user',
  $dbpass = 'password',
  $dbname = 'joomla',
  $dbhost = 'localhost',
) {
  # Install database
  class { '::mysql::server':
    root_password =>  $mysql_root_password,
    remove_default_accounts =>  true,
    override_options =>  $mysql_override_options,
  }

  # Create database, db user and grant permissions
  mysql::db { $dbname:
    user     => $dbuser,
    password => $dbpass,
    host     => $dbhost,
    grant    => ['ALL'],
  }

  # Create support forum user
  user { 'support':
    ensure     => present,
    managehome => true,
  }

  # Install webserver
  class { 'nginx': }

  # Configure VHOST
  nginx::resource::server { 'iobs.observation.org':
    ensure      => present,
    www_root    => '/home/support/www',
    index_files => [ 'index.php' ],
  }

  nginx::resource::location { 'support_root':
    ensure         => present,
    server         => 'iobs.observation.org',
    location       => '~ \.php$',
    fastcgi        => 'unix:/var/run/php/php7.0-fpm.sock',
    fastcgi_index  => ['index.php'],
    fastcgi_params => 'fastcgi_params',
  }
}
