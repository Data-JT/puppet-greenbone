# Install methods

The `greenbone` class supports two install methods, selected with `install_method`. The class
parameters are documented in [REFERENCE.md](../REFERENCE.md#greenbone) and summarised in
[Class parameters](class-parameters.md).

## Docker (tested)

`install_method => 'docker'` is the tested production path. You run the
[Greenbone Community Containers](https://greenbone.github.io/docs/latest/22.4/container/) compose
stack yourself and make gvmd's socket volume reachable from the host. The module then manages only
the GMP transport file and the `gvm_*` resources; every OS-level parameter (`manage_repo` through
`feed_dir`) has no effect.

```puppet
class { 'greenbone':
  install_method => 'docker',
  password       => Sensitive(lookup('greenbone::password')),
  socket         => '/var/lib/docker/volumes/greenbone-community-edition_gvmd_socket_vol/_data/gvmd.sock',
}
```

The socket path above is an example: use the path where your compose project's gvmd socket volume
lives on the host. Use the `admin` account the container stack created as the GMP account, or
create a dedicated one; see [The GMP account](gmp-account.md).

## Native (untested)

`install_method => 'unmanaged'` (the default) manages a native installation on the host. This path
has unit tests but no production use. Its apt repository default
(`https://dl.greenbone.net/repo/CE/stable`) is unverified: Greenbone documents source builds and
containers as its Community Edition install routes. Verify the repository before relying on it,
set `repo_key_id` to the expected signing key fingerprint, or install the packages yourself and set
`manage_repo => false` and `manage_packages => false`.

`greenbone::server` contains every native class and orders them:

```text
greenbone -> database -> redis -> config -> service -> admin -> [ldap] -> feed
```

```puppet
include greenbone::server
```

Supply the credentials through Hiera (`greenbone::password`, `greenbone::admin::password`) and
configure each class through its own parameters. Set `greenbone::server::manage_ldap: true` to
include `greenbone::ldap`. To apply the classes individually instead, keep the same order:

1. `greenbone`: repository, packages, system account, directories, transport file
2. `greenbone::database`: includes `postgresql::server`, creates the `gvm` role and `gvmd`
   database, installs `pg-gvm`, runs `gvmd --migrate`
3. `greenbone::redis`: writes `/etc/redis/redis-openvas.conf`, runs `redis-server@openvas`
4. `greenbone::config`: writes `/etc/openvas/openvas.conf` and `/etc/gvm/gvmd.conf`
5. `greenbone::service`: `notus-scanner`, `ospd-openvas`, `openvasd`, `gvmd`, `gsad`
6. `greenbone::admin`: creates the `admin` account once (guarded by `gvmd --get-users`)
7. `greenbone::feed`: systemd timer for `greenbone-feed-sync`; with `sync_on_install => true` an
   initial sync runs once
8. `gvm_*` resources

The `gvm_*` types need gvmd running and the GMP account present. Let the initial feed sync finish
before naming feed objects (scan configs, port lists) in `gvm_task` or `gvm_target`.

`gvm_admin`, the helper type behind `greenbone::admin`, creates the initial admin account with the
`gvmd` command line before GMP can be used. It passes the password on that command line once, so
it is briefly visible in the process list; rotate the bootstrap password afterwards.

### Debian 13

Set `postgresql::globals::version` (trixie ships `'17'`): puppetlabs/postgresql up to at least
10.5.0 has no default server version for it and fails catalog compilation with "No preferred
version defined or automatically detected".
