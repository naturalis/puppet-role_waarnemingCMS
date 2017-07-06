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

  # Create forum dir
  file { '/home/support/www':
    ensure => directory,
    owner  => 'support',
    group  => 'support',
  }

  # Install PHP with FPM
  class { '::php':
    ensure     => present,
    fpm        => true,
    extensions => {
      mysql  => {},
      mcrypt => {},
      xml    => {},
    },
  }

  # Configure FPM pools
  php::fpm::pool { 'joomla':
    listen      => '/run/php/php7.0-fpm.sock',
    listen_mode => '0666',
    user        => 'support',
    group       => 'support',
  }

  # Install webserver
  class { 'nginx': }

  # Configure VHOST
  nginx::resource::server { 'iobs.observation.org':
    ensure      => present,
    server_name => ['iobs.observation.org', 'support.observation.org', 'cms.example.com'],
    www_root    => '/home/support/www',
    index_files => [ 'index.php' ],
  }

  nginx::resource::location { 'support_root':
    ensure         => present,
    server         => 'iobs.observation.org',
    location       => '~ \.php$',
    include        => ['fastcgi_params'],
    fastcgi        => 'unix:/var/run/php/php7.0-fpm.sock',
    fastcgi_index  => 'index.php',
  }

  # Download and unpack Joomla
  archive { '/tmp/Joomla_3.7.3-Stable-Full_Package.tar.gz':
    ensure        => present,
    extract       => true,
    extract_path  => '/home/support/www',
    source        => 'https://downloads.joomla.org/cms/joomla3/3-7-3/Joomla_3.7.3-Stable-Full_Package.tar.gz',
    checksum      => 'e74a6cfd28e285b23fb3ba117e92c5042c46b804',
    checksum_type => 'sha1',
    creates       => '/home/support/www/index.php',
    cleanup       => true,
    user          => 'support',
    group         => 'support',
    require       => File['/home/support/www'],
  }
}
