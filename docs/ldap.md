# LDAP authentication

How to connect Greenbone to an LDAP server with `greenbone::ldap` and `gvm_ldap`, and let users log
in through it. All attributes are documented in [REFERENCE.md](../REFERENCE.md#gvm_ldap).

Greenbone does not store LDAP settings in a config file: gvmd keeps them in its database and they
are managed over GMP (`describe_auth` / `modify_auth`). The `greenbone::ldap` class drives the
singleton `gvm_ldap` resource, so the main `greenbone` class must be applied first and gvmd must be
running. It works in both install methods.

```puppet
class { 'greenbone::ldap':
  ldaphost        => 'ldap.example.com',
  authdn          => 'uid=%s,ou=people,dc=example,dc=com',
  ldaps_only      => true,
  allow_plaintext => false,
}
```

```yaml
greenbone::ldap::ldaphost: ldap.example.com
greenbone::ldap::authdn: 'uid=%s,ou=people,dc=example,dc=com'
greenbone::ldap::ldaps_only: true
```

To declare the type directly, use the title `ldap_connect`:

```puppet
gvm_ldap { 'ldap_connect':
  ensure          => present,
  ldaphost        => 'ldap.example.com',
  authdn          => 'uid=%s,ou=people,dc=example,dc=com',
  allow_plaintext => false,
}
```

## How gvmd uses the settings

- `ldaphost` is a bare host name (optionally `:port`), never a URI: gvm-libs prepends `ldap://` or
  `ldaps://` itself.
- `authdn` must contain exactly one `%s`, which gvmd replaces with the login name. If the DN
  starts with `uid=`, gvmd first binds anonymously and searches for the user, falling back to the
  template DN; then it binds as the user. There is no bind account and no group mapping.
- Without `ldaps_only`, gvmd tries StartTLS on 389 and falls back to ldaps.
- Leave `cacert` unset to use the system trust store. A set `cacert` becomes the *only* trusted
  CA, and gvmd cannot clear it over GMP once stored.
- `enable => false` on the class, or `ensure => absent` on the type, turns LDAP authentication off
  without discarding the stored host and DN. Local (`file`) users such as the transport user never
  touch LDAP and keep working while it is down.

## LDAP users

Configuring the connection does not by itself let anyone log in: set each user's `source` to
`ldap_connect`.

```puppet
gvm_user { 'bob':
  role_name => 'User',
  source    => 'ldap_connect',
}
```

A `password` on an `ldap_connect` (or `radius_connect`) user is refused: gvmd would store it as a
local hash that starts working whenever LDAP is switched off. To give LDAP users access to the
objects Puppet manages, see [The GMP account](gmp-account.md#sharing-with-other-users).
