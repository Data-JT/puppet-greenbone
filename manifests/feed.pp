# @summary Manages Greenbone feed synchronisation.
#
# Creates a systemd timer that runs greenbone-feed-sync on a configurable
# schedule. Optionally triggers an immediate sync on the first Puppet run
# via an Exec guarded by the presence of feed data.
#
# The feed-sync service runs as $gvm_user under systemd sandboxing.
# Write access is narrowed to $read_write_paths via ProtectSystem=strict.
#
# @param sync_binary
#   Path to the greenbone-feed-sync binary. Must be an absolute path containing
#   only alphanumerics, dots, slashes, underscores, and hyphens.
# @param sync_args
#   Additional arguments passed to greenbone-feed-sync. Each element must
#   contain only letters, digits, and the characters _ . = / : @ , ~ -
#   (spaces and shell metacharacters are rejected at catalog compile time).
# @param calendar
#   Systemd OnCalendar expression for the feed sync timer. Must not contain
#   newlines or control characters.
# @param sync_on_install
#   Run an immediate sync exec if no feed data is present yet.
# @param feed_sentinel
#   File whose existence indicates feed data has been synced at least once.
#   Used as the `creates` guard for the initial sync exec. Must be an absolute
#   path containing only alphanumerics, dots, slashes, underscores, and hyphens.
# @param sync_timeout
#   Timeout in seconds for the initial feed sync exec.
# @param gvm_user
#   System user the feed-sync service runs as. Must be a valid POSIX username.
# @param gvm_group
#   System group for the feed-sync service. Must be a valid POSIX group name.
# @param read_write_paths
#   Paths granted write access under ProtectSystem=strict. Must cover all
#   directories that greenbone-feed-sync writes to. Each element must be an
#   absolute path containing only alphanumerics, dots, slashes, underscores,
#   and hyphens.
class greenbone::feed (
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/] $sync_binary      = '/usr/bin/greenbone-feed-sync',
  Array[String]                        $sync_args        = [],
  String                               $calendar         = 'Sun *-*-* 01:00:00',
  Boolean                              $sync_on_install  = true,
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/] $feed_sentinel    = '/var/lib/gvm/feed/.synced',
  Integer                              $sync_timeout     = 1800,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_user     = $greenbone::gvm_user,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group    = $greenbone::gvm_group,
  Array[String]                        $read_write_paths = ['/var/lib/gvm', '/var/lib/openvas', '/var/cache/notus'],
) {
  $sync_args.each |$arg| {
    unless $arg =~ /\A[A-Za-z0-9_.=\/:@,~-]+\z/ {
      fail("greenbone::feed: sync_args element '${arg}' contains disallowed characters (spaces and shell metacharacters are not permitted)")
    }
  }

  unless $calendar =~ /\A[^\x00-\x1f\x7f\n\r]+\z/ {
    fail("greenbone::feed: calendar '${calendar}' contains control characters")
  }

  $read_write_paths.each |$path| {
    unless $path =~ /\A\/[A-Za-z0-9_.\/\-]+\z/ {
      fail("greenbone::feed: read_write_paths element '${path}' is not a valid absolute path")
    }
  }

  $initial_sync_require = if defined(Package['greenbone-feed-sync']) {
    [Package['greenbone-feed-sync'], Service['gvmd']]
  } else {
    [Service['gvmd']]
  }

  file { '/etc/systemd/system/greenbone-feed-sync.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('greenbone/feed-sync.service.epp', {
        'sync_binary'      => $sync_binary,
        'sync_args'        => $sync_args,
        'gvm_user'         => $gvm_user,
        'read_write_paths' => $read_write_paths,
    }),
    notify  => Exec['systemd-daemon-reload-greenbone-feed'],
  }

  file { '/etc/systemd/system/greenbone-feed-sync.timer':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('greenbone/feed-sync.timer.epp', {
        'calendar' => $calendar,
    }),
    require => File['/etc/systemd/system/greenbone-feed-sync.service'],
    notify  => [
      Exec['systemd-daemon-reload-greenbone-feed'],
      Service['greenbone-feed-sync.timer'],
    ],
  }

  exec { 'systemd-daemon-reload-greenbone-feed':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    before      => Service['greenbone-feed-sync.timer'],
  }

  service { 'greenbone-feed-sync.timer':
    ensure  => running,
    enable  => true,
    require => File['/etc/systemd/system/greenbone-feed-sync.timer'],
  }

  if $sync_on_install {
    $sync_cmd = if empty($sync_args) {
      $sync_binary
    } else {
      "${sync_binary} ${sync_args.join(' ')}"
    }

    # Run sync as the unprivileged gvm_user, not root.
    # The sentinel is touched in a separate exec so the sync command contains no
    # shell metacharacters that could be exploited via a crafted Hiera value.
    exec { 'greenbone-feed-sync-initial':
      command => $sync_cmd,
      creates => $feed_sentinel,
      user    => $gvm_user,
      group   => $gvm_group,
      timeout => $sync_timeout,
      require => $initial_sync_require,
    }

    exec { 'greenbone-feed-sync-sentinel':
      command => "/usr/bin/touch ${feed_sentinel}",
      creates => $feed_sentinel,
      user    => $gvm_user,
      group   => $gvm_group,
      require => Exec['greenbone-feed-sync-initial'],
    }
  }
}
