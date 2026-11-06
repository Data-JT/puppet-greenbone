# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'
require_relative 'gvm_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'gvm_user',
  features: ['custom_insync'],
  docs:  'Manages a GVM user account.',

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this GVM user should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'GVM username.',
      behaviour: :namevar,
    },
    password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      <<~DESC,
        User password. Write-only: sent on create and on every update, but because
        GMP never returns it the value cannot be compared, so changing only the
        password will NOT by itself trigger an update — combine a rotation with
        another attribute change, or recreate the user.
      DESC
      behaviour: :parameter,
      sensitive: true,
    },
    role_name: {
      type:    'String',
      desc:    'Name of the GVM role to assign (e.g. "Admin", "User", "Observer").',
      default: 'User',
    },
    hosts: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of hosts the user may access. Empty means all hosts.',
    },
    hosts_allow: {
      type:    'Boolean',
      desc:    'When true, hosts list is an allowlist; when false it is a denylist.',
      default: true,
    },
    source: {
      type:    'Enum[file, ldap_connect, radius_connect]',
      desc:    <<~DESC,
        Authentication source for the user. "file" uses the local GVM password;
        "ldap_connect" / "radius_connect" delegate authentication to the configured
        LDAP / RADIUS server (see the greenbone::ldap class for the connection
        setup). For LDAP/RADIUS users the password is unused.
      DESC
      default: 'file',
    },
    delete_properties: {
      type: "Optional[Array[Enum['hosts']]]",
      desc: <<~DESC,
        Optional properties to clear on update, by attribute name. Removing an
        attribute from the manifest only stops Puppet managing it. Only `hosts` can
        be cleared, which gives the user access to all hosts.
      DESC
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_user)
Puppet::Type::GvmSensitiveParameters.register(:gvm_user)
