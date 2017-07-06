# == Class: role_waarnemingCMS
#
# This role creates the necessary configuration for the support.observation.org webservice.
#
class role_waarnemingcms (
  $mysql_root_password = 'password',
  $mysql_override_options = {
  },
  $system_user = 'support',
  $web_root = "/home/${system_user}/www",
  $dbuser = 'user',
  $dbpass = 'password',
  $dbname = 'joomla',
  $dbpref = 'sup_',
  $dbhost = 'localhost',
  $joomla_secret = undef,
  $joomla_mailfrom = undef,
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
  user { $system_user:
    ensure     => present,
    managehome => true,
  }

  # Create forum dir
  file { $web_root:
    ensure => directory,
    owner  => $system_user,
    group  => $system_user,
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
    user        => $system_user,
    group       => $system_user,
  }

  # Install memcached for caching and user sessions
  class { 'memcached': }

  # Install webserver
  class { 'nginx':
    keepalive_timeout    => '60',
  }

  # Configure VHOST
  nginx::resource::server { 'iobs.observation.org':
    ensure               => present,
    server_name          => ['iobs.observation.org', 'support.observation.org', 'cms.example.com'],
    use_default_location => false,
    www_root             => $web_root,
    server_cfg_prepend   => {
      server_name_in_redirect => 'off',
    },
    locations            => {
      support_root => {
        location      => '~ \.php$',
        fastcgi       => 'unix:/var/run/php/php7.0-fpm.sock',
        fastcgi_index => 'index.php',
        www_root      => undef,
        index_files   => undef,
      },
      clean_urls   => {
        location    => '/',
        try_files   => ['$uri $uri/ /index.php?$args'],
        www_root    => undef,
        index_files => undef,
      },
      deny_scripts => {
        location            => '~* /(images|cache|media|logs|tmp)/.*\.(php|pl|py|jsp|asp|sh|cgi)$',
        location_custom_cfg => {
          return     => '403',
          error_page => '403 /403_error.html',
        },
        www_root            => undef,
        index_files         => undef,
      },
      long_cache   => {
        location    => '~* \.(ico|pdf|flv)$',
        expires     => '1y',
        www_root    => undef,
        index_files => undef,
      },
      short_cache  => {
        location    => '~* \.(js|css|png|jpg|jpeg|gif|swf|xml|txt)$',
        expires     => '14d',
        www_root    => undef,
        index_files => undef,
      },
    }
  }

  # Download and unpack Joomla
  archive { '/tmp/Joomla_3.7.3-Stable-Full_Package.tar.gz':
    ensure        => present,
    extract       => true,
    extract_path  => $web_root,
    source        => 'https://downloads.joomla.org/cms/joomla3/3-7-3/Joomla_3.7.3-Stable-Full_Package.tar.gz',
    checksum      => 'e74a6cfd28e285b23fb3ba117e92c5042c46b804',
    checksum_type => 'sha1',
    creates       => "${web_root}/index.php",
    cleanup       => true,
    user          => $system_user,
    group         => $system_user,
    require       => File[$web_root],
  }

  # Create Joomla configuration
  file { "${web_root}/configuration.php":
    content => template('role_waarnemingcms/configuration.php.erb'),
    owner   => $system_user,
    group   => $system_user,
    mode    => '0644',
  }

  # Place site specific images
  file {
    "${web_root}/images/iObs-icon-vectortitle-RGB-h-180x60.png": source => 'puppet:///modules/role_waarnemingcms/iObs-icon-vectortitle-RGB-h-180x60.png';
    "${web_root}/templates/protostar/favicon.ico": source               => 'puppet:///modules/role_waarnemingcms/favicon.ico';
  }
}
