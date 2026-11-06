# @summary Configures the PostgreSQL database for gvmd.
#
# Creates the gvm PostgreSQL user and gvmd database, installs the pg-gvm
# extension, and runs `gvmd --migrate` once to initialise or upgrade the
# schema. Requires the puppetlabs/postgresql module.
#
# The `gvmd --migrate` exec runs as the gvm system user. PostgreSQL peer
# authentication is used by default so no database password is required.
#
# The dba superuser role is granted to the gvm database user only for the
# duration of `gvmd --migrate` and revoked immediately afterward, so the
# gvm process holds no persistent superuser membership at runtime.
#
# @param db_name
#   Name of the PostgreSQL database. Must be a valid PostgreSQL identifier
#   (letters, digits, underscores; must start with a letter or underscore).
# @param db_user
#   PostgreSQL role that owns the database. Same identifier constraints as
#   db_name. The value is embedded as a double-quoted SQL identifier.
# @param gvm_user
#   System user used to run gvmd commands. Must be a valid POSIX username.
# @param gvm_group
#   System group for gvmd. Must be a valid POSIX group name.
# @param gvmd_bin
#   Absolute path to the gvmd binary.
# @param migrate_timeout
#   Timeout in seconds for the gvmd --migrate exec resource.
# @param psql_path
#   Absolute path to the psql binary.
# @param migrate_script
#   Absolute path where the migration wrapper script is written.
# @param migrate_sentinel
#   File the wrapper touches after a successful migration. Used as the `creates`
#   guard when the gvmd package is not managed by Puppet, so the migration runs
#   once rather than on every catalog application.
class greenbone::database (
  Pattern[/\A[A-Za-z_][A-Za-z0-9_]*\z/]   $db_name          = 'gvmd',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_]*\z/]   $db_user          = 'gvm',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_user         = $greenbone::gvm_user,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group        = $greenbone::gvm_group,
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/]     $gvmd_bin         = '/usr/sbin/gvmd',
  Integer                                 $migrate_timeout  = 300,
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/]     $psql_path        = '/usr/bin/psql',
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/]     $migrate_script   = '/usr/local/sbin/gvm-migrate',
  Pattern[/\A\/[A-Za-z0-9_.\/\-]+\z/]     $migrate_sentinel = "${greenbone::data_dir}/gvmd/.schema-migrated",
) {
  include postgresql::server

  $pg_gvm_require = if defined(Package['pg-gvm']) {
    [Postgresql::Server::Db[$db_name], Package['pg-gvm']]
  } else {
    [Postgresql::Server::Db[$db_name]]
  }

  $gvmd_pkg_require = if defined(Package['gvmd']) {
    [Package['gvmd']]
  } else {
    []
  }

  postgresql::server::role { $db_user:
    login => true,
    db    => 'postgres',
  }

  postgresql::server::db { $db_name:
    user     => $db_user,
    password => undef,
    require  => Postgresql::Server::Role[$db_user],
  }

  postgresql::server::extension { 'pg-gvm':
    database  => $db_name,
    extension => 'pg_gvm',
    require   => $pg_gvm_require,
  }

  # DBA superuser role is needed by pg-gvm only during schema migration.
  # The migration wrapper script grants dba immediately before gvmd --migrate
  # and revokes it via a bash trap that fires on both success and failure, so
  # the gvm account never holds persistent superuser membership at runtime.
  postgresql::server::role { 'dba':
    superuser => true,
    inherit   => false,
  }

  # Migration wrapper: grant dba, run gvmd --migrate, always revoke dba.
  # Template values are validated by Pattern types above — no shell injection
  # is possible through Hiera. The script uses runuser for privilege separation.
  file { $migrate_script:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0700',
    content => epp('greenbone/gvm-migrate.sh.epp', {
        'psql_path'        => $psql_path,
        'gvmd_bin'         => $gvmd_bin,
        'db_user'          => $db_user,
        'gvm_user'         => $gvm_user,
        'migrate_sentinel' => $migrate_sentinel,
    }),
  }

  # Idempotency: when Puppet manages the gvmd package, run the migration only
  # when that package changes (fresh install or upgrade) instead of on every
  # run. When the package is managed out of band, fall back to a one-shot
  # `creates` guard on the sentinel the wrapper touches on success.
  $migrate_trigger = defined(Package['gvmd']) ? {
    true    => { 'refreshonly' => true, 'subscribe' => Package['gvmd'] },
    default => { 'creates' => $migrate_sentinel },
  }

  exec { 'gvmd-migrate':
    command => $migrate_script,
    timeout => $migrate_timeout,
    require => [
      Postgresql::Server::Role['dba'],
      Postgresql::Server::Role[$db_user],
      Postgresql::Server::Extension['pg-gvm'],
      File[$migrate_script],
    ] + $gvmd_pkg_require,
    *       => $migrate_trigger,
  }
}
