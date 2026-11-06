# Class parameters

Parameters of the main `greenbone` class. The generated reference, including the sub-classes, is
in [REFERENCE.md](../REFERENCE.md#greenbone); this page adds the context around it.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `password` | `Sensitive[String]` | — | GMP password for `user` (the `password` key of the transport file) |
| `user` | `String[1]` | `'admin'` | GVM account the providers authenticate as over GMP (the `user` key of the transport file) |
| `socket` | `Pattern[/\A\//]` (absolute path) | `'/run/gvmd/gvmd.sock'` | Path to the gvmd Unix socket (the `socket` key of the transport file) |
| `config_file` | `Pattern[/\A\//]` (absolute path) | `<agent confdir>/gvm_transport.yaml` | Where the transport file is written; must be the path the agent's providers read |
| `install_method` | `Enum['unmanaged', 'docker']` | `'unmanaged'` | `'unmanaged'`: native install on the host; `'docker'`: skip every OS-level resource and manage only the transport file |
| `manage_repo` | `Boolean` | `true` | Manage the Greenbone apt repository (native install only) |
| `repo_location` | `Pattern[/\Ahttps?:\/\/\S+\z/]` | `'https://dl.greenbone.net/repo/CE/stable'` | Apt repository URL (unverified default) |
| `repo_key_source` | `Pattern[/\Ahttps?:\/\/\S+\z/]` | `'https://dl.greenbone.net/repo/CE/stable/greenbone-community-edition-keyring.gpg'` | URL of the repository signing key |
| `repo_key_id` | `Optional[String]` | `undef` | Expected key fingerprint (40 hex characters); recommended |
| `repo_release` | `Optional[String]` | `$facts['os']['distro']['codename']` | Apt release, e.g. `'bookworm'` |
| `manage_packages` | `Boolean` | `true` | Manage the Greenbone packages (native install only) |
| `packages` | `Hash[String, String]` | `gvmd`, `gsad`, `openvas-scanner`, `ospd-openvas`, `notus-scanner`, `greenbone-feed-sync`, `pg-gvm` | Package name => ensure value |
| `gvm_user` | `Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/]` | `'gvm'` | System account that runs the Greenbone services and owns their files; not a GVM account |
| `gvm_group` | `Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/]` | `'gvm'` | System group for the Greenbone services |
| `data_dir` | `Pattern[/\A\//]` | `'/var/lib/gvm'` | Base directory for persistent data |
| `log_dir` | `Pattern[/\A\//]` | `'/var/log/gvm'` | Log directory |
| `run_dir` | `Pattern[/\A\//]` | `'/run/gvm'` | Runtime directory (sockets, PIDs) |
| `feed_dir` | `Pattern[/\A\//]` | `'/var/lib/gvm/feed'` | Feed data directory |

`user` and `gvm_user` are unrelated: `user` is the GVM login used over GMP, `gvm_user` is the Unix
account the services run as. In docker mode the OS-level parameters (`manage_repo` through
`feed_dir`) have no effect.

`password` must be `Sensitive`. When it comes from Hiera, convert it with `lookup_options`:

```yaml
lookup_options:
  greenbone::password:
    convert_to: Sensitive

greenbone::password: ENC[PKCS7,...]
```

In a manifest, wrap it explicitly:

```puppet
class { 'greenbone':
  install_method => 'docker',
  password       => Sensitive(lookup('greenbone::password')),
  socket         => '/var/lib/docker/volumes/greenbone-community-edition_gvmd_socket_vol/_data/gvmd.sock',
}
```

## The transport file

The class writes `user`, `password` and `socket` to `config_file` (`root:root`, mode `0600`), which
the providers read at agent run time. Declare the class on the Greenbone node, in `site.pp`, a
role or a profile.

- All `gvm_*` types automatically require the managed transport file when it is present in the
  catalog, so a single `puppet agent -t` applies the class and all `gvm_*` resources in the same
  pass.
- The providers always read `gvm_transport.yaml` from the agent's own confdir, so do not point
  `config_file` anywhere else.
- The default comes from the `greenbone_confdir` fact, which reports the agent's own
  `Puppet[:confdir]`; only before that fact has been pluginsynced does it fall back to the
  compiling server's `$settings::confdir`.
