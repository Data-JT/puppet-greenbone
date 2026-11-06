# @summary Configures a dedicated Redis instance for OpenVAS.
#
# Manages /etc/redis/redis-openvas.conf and the redis-server@openvas
# systemd service. OpenVAS uses a Unix socket for fast local IPC with Redis.
#
# @param socket_path
#   Unix socket path Redis listens on.
# @param socket_perm
#   Permissions on the Redis socket (must allow the gvm group to connect).
# @param unixsocketgroup
#   Group that owns the Redis socket.
# @param save
#   Whether to enable Redis persistence (RDB snapshots). Disabled by default
#   since feed data is repopulated on sync; persistence only adds I/O cost.
# @param log_level
#   Redis log level (debug, verbose, notice, warning). Named log_level rather
#   than loglevel because loglevel is a Puppet metaparameter.
# @param maxmemory
#   Optional Redis maxmemory limit (e.g. '512mb'). Unset by default.
# @param config_file
#   Path to the Redis configuration file managed by this class.
# @param gvm_group
#   System group for Greenbone services; granted access to the socket.
class greenbone::redis (
  Pattern[/\A\//]                         $socket_path     = '/run/redis-openvas/redis.sock',
  Pattern[/\A[0-7]{3,4}\z/]               $socket_perm     = '0770',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $unixsocketgroup = $greenbone::gvm_group,
  Boolean                                 $save            = false,
  String                                  $log_level       = 'notice',
  Optional[String]                        $maxmemory       = undef,
  Pattern[/\A\//]                         $config_file     = '/etc/redis/redis-openvas.conf',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group       = $greenbone::gvm_group,
) {
  package { 'redis-server':
    ensure => present,
  }

  # Directory for the openvas Redis socket
  file { '/run/redis-openvas':
    ensure => directory,
    owner  => 'redis',
    group  => $gvm_group,
    mode   => '0770',
  }

  file { $config_file:
    ensure  => file,
    owner   => 'redis',
    group   => $gvm_group,
    mode    => '0640',
    content => epp('greenbone/redis-openvas.conf.epp', {
        'socket_path'     => $socket_path,
        'socket_perm'     => $socket_perm,
        'unixsocketgroup' => $unixsocketgroup,
        'save'            => $save,
        'loglevel'        => $log_level,
        'maxmemory'       => $maxmemory,
    }),
    require => Package['redis-server'],
    notify  => Service['redis-server@openvas'],
  }

  service { 'redis-server@openvas':
    ensure  => running,
    enable  => true,
    require => File[$config_file],
  }
}
