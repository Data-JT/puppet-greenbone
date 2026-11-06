# @summary Manages the Greenbone LDAP authentication connection.
#
# Configures gvmd's `ldap_connect` authentication method over GMP. Greenbone
# stores LDAP settings in its database (not a config file), so this class drives
# the singleton `gvm_ldap` resource rather than writing a template.
#
# Apply this only after the `greenbone` class (for the transport credentials) and
# once gvmd is running, so the GMP `modify_auth` call succeeds. When included via
# `greenbone::server` with `manage_ldap => true`, that ordering is wired for you.
#
# Enabling LDAP lets nobody in by itself: each LDAP user must also exist in gvmd
# as a gvm_user with `source => 'ldap_connect'`, and gets its role there.
#
# @param enable
#   Whether LDAP authentication is enabled. false disables it without discarding
#   the stored host/DN.
# @param ldaphost
#   LDAP server host name, optionally with :port -- not a URI; gvm-libs adds
#   ldap:// or ldaps:// itself. Required when enabling.
# @param authdn
#   Bind DN template with exactly one '%s', which gvmd replaces with the login
#   name, e.g. 'uid=%s,ou=people,dc=example,dc=org'. Required when enabling.
# @param cacert
#   PEM CA certificate, used as the only trusted CA for the LDAP connection.
#   Leave unset to use the system trust store. A stored cacert cannot be
#   cleared over GMP; see gvm_ldap.
# @param allow_plaintext
#   Whether to permit LDAP connections without TLS. Keep false unless you understand
#   the exposure.
# @param ldaps_only
#   Use ldaps (636) only instead of trying StartTLS on 389 first.
#
# @example Hiera data
#   greenbone::ldap::ldaphost:   'ldap.example.org'
#   greenbone::ldap::authdn:     'uid=%s,ou=people,dc=example,dc=org'
#   greenbone::ldap::ldaps_only: true
class greenbone::ldap (
  Boolean          $enable          = true,
  Optional[String] $ldaphost        = undef,
  Optional[String] $authdn          = undef,
  Optional[String] $cacert          = undef,
  Boolean          $allow_plaintext = false,
  Boolean          $ldaps_only      = false,
) {
  include greenbone

  $ensure = $enable ? { true => 'present', default => 'absent' }

  gvm_ldap { 'ldap_connect':
    ensure          => $ensure,
    ldaphost        => $ldaphost,
    authdn          => $authdn,
    cacert          => $cacert,
    allow_plaintext => $allow_plaintext,
    ldaps_only      => $ldaps_only,
  }
}
