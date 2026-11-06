# @summary Convenience class that applies the full Greenbone stack in order.
#
# Includes and `contain`s every Greenbone sub-class and wires the cross-class
# ordering so the whole stack can be referenced as a single unit and applies
# deterministically regardless of declaration order:
#
#   greenbone -> database -> redis -> config -> service -> admin -> [ldap] -> feed
#
# Configure each concern through its own class parameters (typically via Hiera).
# The required credentials must be available for automatic class-parameter lookup
# before including this class:
#   * greenbone::password
#   * greenbone::admin::password
#
# @param manage_ldap
#   Whether to include and order `greenbone::ldap` in the stack. Defaults to false;
#   set true and supply `greenbone::ldap::*` parameters (via Hiera) to manage the
#   LDAP authentication connection.
#
# @example
#   include greenbone::server
class greenbone::server (
  Boolean $manage_ldap = false,
) {
  contain greenbone
  contain greenbone::database
  contain greenbone::redis
  contain greenbone::config
  contain greenbone::service
  contain greenbone::admin
  contain greenbone::feed

  Class['greenbone']
  -> Class['greenbone::database']
  -> Class['greenbone::redis']
  -> Class['greenbone::config']
  -> Class['greenbone::service']
  -> Class['greenbone::admin']
  -> Class['greenbone::feed']

  if $manage_ldap {
    contain greenbone::ldap

    Class['greenbone::admin']
    -> Class['greenbone::ldap']
    -> Class['greenbone::feed']
  }
}
