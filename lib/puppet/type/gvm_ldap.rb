# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_ldap',
  features: ['canonicalize'],
  docs:     <<~DOCS,
    Manages the Greenbone LDAP (ldap_connect) authentication configuration via
    GMP. gvmd keeps these settings in its database (the `meta` table), read and
    written over GMP describe_auth / modify_auth. This is a singleton: declare
    exactly one, titled "ldap_connect". ensure => present enables LDAP
    authentication and pushes the connection settings; ensure => absent only
    sets enable to false and keeps the stored host/DN.

    What gvmd does with it (gvmd 26.42 / gvm-libs ldaputils.c): the login name
    replaces `%s` in authdn. If the DN starts with `uid=`, gvmd first binds
    anonymously and searches for the uid below the rest of the DN, falling back
    to the template DN when the search finds nothing; then it does a simple
    bind with the user's password. There is no bind account and no group
    mapping -- each user must exist in gvmd with source ldap_connect (gvm_user),
    and gets its role there.

    LDAP is only one method: users with source file (the transport user, admin)
    never touch LDAP and keep working when the directory is down.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether LDAP authentication is enabled (present) or disabled (absent).',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Name of the auth method group. Use "ldap_connect".',
      behaviour: :namevar,
    },
    ldaphost: {
      # gvm-libs builds the URI itself ("ldap://%s" / "ldaps://%s"), so a URI
      # here becomes ldap://ldaps://host and every login fails.
      type: 'Optional[Pattern[/\A[A-Za-z0-9.-]+(:[0-9]+)?\z/]]',
      desc: 'LDAP server host name, optionally with :port -- NOT a URI; gvm-libs adds the scheme itself. Required when ensure => present.',
    },
    authdn: {
      type: 'Optional[Pattern[/\A[^%]*%s[^%]*\z/]]',
      desc: <<~DESC,
        Bind DN template with exactly one "%s", which gvmd replaces with the login
        name, e.g. "uid=%s,ou=people,dc=example,dc=org". gvmd rejects any other "%"
        at login time. Required when ensure => present.
      DESC
    },
    cacert: {
      type: 'Optional[String]',
      desc: <<~DESC,
        PEM CA certificate gvmd uses as the ONLY trusted CA for the LDAP TLS
        connection. Unset means libldap's default trust store (the system CA
        bundle). Compared against what describe_auth returns. gvmd cannot clear a
        stored cacert over GMP (an empty value is rejected as an invalid
        certificate), so think before setting one: removing it from the
        manifest leaves it in place.
      DESC
    },
    allow_plaintext: {
      type:    'Boolean',
      desc:    'Whether gvmd may fall back to an unencrypted connection when StartTLS fails. Leave false.',
      default: false,
    },
    ldaps_only: {
      type:    'Boolean',
      desc:    'Use ldaps (636) only. When false, gvmd tries StartTLS on 389 first and falls back to ldaps.',
      default: false,
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_ldap)
