# @summary Manages OpenVAS and gvmd configuration files.
#
# Writes /etc/openvas/openvas.conf (used by openvas-scanner and ospd-openvas)
# and /etc/gvm/gvmd.conf. Changes notify the affected services.
#
# @param redis_socket
#   Path to the Redis Unix socket. Must match greenbone::redis::socket_path.
# @param scanner_socket
#   Path to the ospd-openvas Unix socket that gvmd connects to.
# @param gvmd_socket
#   Path to the gvmd management Unix socket.
# @param log_level
#   OpenVAS log level (Debug, Info, Warning, Error).
# @param max_hosts
#   Maximum number of hosts scanned in parallel.
# @param max_checks
#   Maximum number of checks performed against each host in parallel.
# @param openvas_conf
#   Additional key/value pairs written into openvas.conf.
# @param gvm_user
#   System user that owns the config files.
# @param gvm_group
#   System group for config file group ownership.
class greenbone::config (
  Pattern[/\A\//]                         $redis_socket   = '/run/redis-openvas/redis.sock',
  Pattern[/\A\//]                         $scanner_socket = '/run/ospd/ospd-openvas.sock',
  Pattern[/\A\//]                         $gvmd_socket    = '/run/gvmd/gvmd.sock',
  String                                  $log_level      = 'Warning',
  Integer                                 $max_hosts      = 30,
  Integer                                 $max_checks     = 10,
  Hash[String, String]                    $openvas_conf   = {},
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_user       = $greenbone::gvm_user,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group      = $greenbone::gvm_group,
) {
  $base_openvas_conf = {
    'db_address' => $redis_socket,
    'log_level'  => $log_level,
    'max_hosts'  => String($max_hosts),
    'max_checks' => String($max_checks),
  }
  $merged_openvas_conf = $base_openvas_conf + $openvas_conf

  file { '/etc/openvas/openvas.conf':
    ensure  => file,
    owner   => $gvm_user,
    group   => $gvm_group,
    mode    => '0640',
    content => epp('greenbone/openvas.conf.epp', {
        'settings' => $merged_openvas_conf,
    }),
    require => File['/etc/openvas'],
  }

  # gvmd.conf holds scanner and socket paths consumed by the systemd unit
  file { '/etc/gvm/gvmd.conf':
    ensure  => file,
    owner   => $gvm_user,
    group   => $gvm_group,
    mode    => '0640',
    content => epp('greenbone/gvmd.conf.epp', {
        'scanner_socket' => $scanner_socket,
        'gvmd_socket'    => $gvmd_socket,
    }),
    require => File['/etc/gvm'],
  }
}
