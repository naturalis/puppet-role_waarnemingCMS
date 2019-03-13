# == Class: role_waarnemingcms
#
# This role creates the necessary configuration for the support.observation.org webservice.
#
class role_waarnemingcms (
  $mysql_root_password = undef,
  $mysql_override_options = {
  },
  $system_user = 'support',
  $defaults = { require => Package['nginx'] },
  $web_root = "/home/${system_user}/www",
  $server_name = ['iobs.observation.org', 'support.observation.org'],
  $dbuser = undef,
  $dbpass = undef,
  $dbname = 'joomla',
  $dbpref = 'sup_',
  $dbhost = 'localhost',
  $joomla_version = '3.8.0',
  $joomla_checksum = 'e74a6cfd28e285b23fb3ba117e92c5042c46b804',
  $joomla_secret = undef,
  $joomla_mailfrom = undef,
) {

  # Defaults for all file resources
  File {
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    notify => Service['nginx'],
  }

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
    },
    fpm_pools  => {
      www    => {
        ensure => absent,
      },
      joomla => {
        listen      => '/run/php/php7.0-fpm.sock',
        listen_mode => '0666',
        user        => $system_user,
        group       => $system_user,
      },
    },
  }

  # Install memcached for caching and user sessions
  class { 'memcached': }

  # Install webserver
  class { 'nginx':
    keepalive_timeout => '60',
  }

  file { '/etc/nginx/ssl':
    ensure  => directory,
    require => Package['nginx'],
  }

  # Configure VHOST
  nginx::resource::server { 'joomla':
    ensure               => present,
    server_name          => $server_name,
    use_default_location => false,
    www_root             => $web_root,
    ssl                  => true,
    ssl_cert             => '/etc/letsencrypt/live/support.observation.org/fullchain.pem',
    ssl_key              => '/etc/letsencrypt/live/support.observation.org/privkey.pem',
    ssl_redirect         => true,
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
        index_files => undef,
      },
      short_cache  => {
        location    => '~* \.(js|css|png|jpg|jpeg|gif|swf|xml|txt)$',
        expires     => '14d',
        index_files => undef,
      },
    },
#    require              => [ File['/etc/nginx/ssl/observation_org-chained.crt'], File['/etc/nginx/ssl/observation_org.key'] ],
  }

  # Download and unpack Joomla
  $joomla_version_dashed = regsubst($joomla_version,'\.', '-', 'G')
  $joomla_version_major = split($joomla_version, '\.')[0]

  archive { "/tmp/Joomla_${joomla_version}-Stable-Full_Package.tar.gz":
    ensure        => present,
    extract       => true,
    extract_path  => $web_root,
    source        => "https://downloads.joomla.org/cms/joomla${joomla_version_major}/${joomla_version_dashed}/Joomla_${joomla_version}-Stable-Full_Package.tar.gz",
    checksum      => $joomla_checksum,
    checksum_type => 'sha1',
    creates       => "${web_root}/index.php",
    cleanup       => true,
    user          => $system_user,
    group         => $system_user,
    require       => File[$web_root],
  }

  # Remove installation directory
  file { "${web_root}/installation":
    ensure  => absent,
    recurse => true,
    force   => true,
    require => Archive["/tmp/Joomla_${joomla_version}-Stable-Full_Package.tar.gz"],
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
    "${web_root}/images/iobs": ensure => directory, source => 'puppet:///modules/role_waarnemingcms/iobs', recurse => true;
  }

  file { "${web_root}/templates/protostar/favicon.ico":
    source => 'puppet:///modules/role_waarnemingcms/favicon.ico',
    owner   => 'www-data',
    group   => 'www-data',
    mode    => '0666',
  }

  # Create SMF version checker for sensu
  file { "/usr/local/sbin/chkjoomlaversion.sh":
    content => template('role_waarnemingcms/chkjoomlaversion.erb'),
    mode    => '0755',
  }

  # export check so sensu monitoring can make use of it
  @@sensu::check { 'Check Joomla version' :
    command     => '/usr/local/sbin/chkjoomlaversion.sh',
    handlers    => 'default',
    tag         => 'central_sensu',
  }


}
