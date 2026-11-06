<a href="https://www.data-jt.de">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-dark.svg">
    <img alt="Data JT" src="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-light.svg" width="420">
  </picture>
</a>

# datajt-greenbone

Manage Greenbone Community Edition (OpenVAS) scan configuration as Puppet code, through the GMP socket.

## Table of contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [Resource types and classes](#resource-types-and-classes)
5. [Further documentation](#further-documentation)
6. [Limitations](#limitations)
7. [Contributing](#contributing)
8. [License](#license)
9. [About Data JT](#about-data-jt)

## Description

This module lets you describe the configuration of a [Greenbone Community Edition](https://community.greenbone.net/)
vulnerability scanner in Puppet code or Hiera: scan schedules, targets, tasks and tuned scan
configs, GVM users, groups and permissions, saved filters, user settings, severity overrides and
the LDAP authentication connection. The Puppet agent on the Greenbone host compares that
description with what gvmd stores and changes only what differs.

Greenbone rebranded the free edition as OpenVAS Community Edition in 2025; the packages,
paths and the GMP protocol still carry the `greenbone` and `gvm` names, and so does this module.

### What it does

- Manages 11 kinds of GVM objects as native Puppet resource types (`gvm_*`), over the Greenbone
  Management Protocol (GMP) on gvmd's local Unix socket.
- Declares all of them from Hiera through one class, `greenbone::resources`.
- Resolves references by name (a task names its target, scan config, scanner and schedule), so
  the data contains no GVM UUIDs.
- Optionally installs and configures a native Greenbone stack (apt repository, packages,
  PostgreSQL, Redis, config files, services, admin account, feed sync) with standard Puppet
  resources. The Docker install method, where you run the official compose stack yourself, is the
  tested production path.

### What it does not do

- It does not run or manage the Greenbone Community Containers; in docker mode it manages only
  the GMP transport file and the `gvm_*` resources.
- It does not manage feed content (the built-in scan configs, port lists and NVTs), scan results
  or reports. Scan configs are cloned from a feed config and only the listed preferences are managed.
- It does not use `puppet device`, a proxy agent or a Bolt transport. The agent runs on the
  Greenbone host; there is no network API to expose.
- It does not purge GVM objects that are not declared in Puppet, and it never touches overrides or
  permissions created in the web UI.
- It does not clear a value when you remove an attribute; use `delete_properties` for that.
- It cannot compare `gvm_user` passwords: GMP never returns them.

### How it works

```text
Hiera / manifest   declares the class and the resources
      │
      ▼
greenbone class    writes gvm_transport.yaml (GMP user and password, 0600)
      │
      ▼
gvm_* types        read that file on every agent run on the Greenbone host
      │
      ▼
gvmd               Unix socket (GMP)
```

The `greenbone` class writes the GMP credentials and socket path to a transport file in the
agent's confdir. The `gvm_*` types are built on the Puppet Resource API; their providers open
gvmd's Unix socket, log in as the configured GVM account and compare or change objects on every
agent run. Every object they create is owned by that account. Resources come from manifests or
from Hiera via `greenbone::resources`.

## Requirements

- Puppet or OpenVox 8 or 9 (`>= 8.0.0 < 10.0.0`). Testing is currently done on 8 (CI and production); on 9 the unit tests also run in CI
  (OpenVox 9.3), but there is no production use yet. Forge dependencies: `puppetlabs/stdlib`, `puppetlabs/apt` and `puppetlabs/postgresql`
  (the latter two are used by the native install classes only).
- Debian 12 or 13.
- A running gvmd whose Unix socket the Puppet agent can open on the same host (the agent runs as
  root in the standard setup), and a GVM account for the providers; see
  [the GMP account](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/gmp-account.md).

## Quick start

### 1. Install Greenbone

Run the [Greenbone Community Containers](https://greenbone.github.io/docs/latest/22.4/container/)
compose stack and note the host path of the `gvmd.sock` socket volume. The `admin` account the
stack creates can serve as the GMP account. The native install path is described in
[Install methods](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/install-methods.md).

### 2. Manifest

```puppet
# site/profile/manifests/greenbone.pp
class profile::greenbone {
  include greenbone            # transport: install_method, socket, user, password from Hiera
  include greenbone::resources # gvm_* resources from Hiera

  # Resources can also be declared directly:
  gvm_target { 'internal-servers':
    hosts          => '192.0.2.0/24',
    port_list_name => 'All IANA assigned TCP',
  }
}
```

### 3. Hiera

```yaml
# Class parameters. Keep the password encrypted (hiera-eyaml) and convert it to Sensitive.
lookup_options:
  greenbone::password:
    convert_to: Sensitive

greenbone::install_method: docker
greenbone::socket: /var/lib/docker/volumes/greenbone-community-edition_gvmd_socket_vol/_data/gvmd.sock
greenbone::password: ENC[PKCS7,...]

# Resources
greenbone::resources::schedules:
  'Weekly Monday 02:00':
    icalendar: |
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Puppet Greenbone Profile//EN
      BEGIN:VEVENT
      DTSTART:20260105T020000
      RRULE:FREQ=WEEKLY;BYDAY=MO
      END:VEVENT
      END:VCALENDAR
    timezone: Europe/Berlin

greenbone::resources::targets:
  internal-servers:
    hosts: '198.51.100.0/24, 203.0.113.0/24'
    exclude_hosts: 198.51.100.5
    port_list_name: All IANA assigned TCP
    alive_test: ICMP Ping

greenbone::resources::tasks:
  weekly-internal:
    target_name: internal-servers
    config_name: Full and fast
    scanner_name: OpenVAS Default
    schedule_name: 'Weekly Monday 02:00'

greenbone::resources::users:
  alice:
    role_name: User
    source: ldap_connect
```

`ensure` defaults to `present`. The resources class orders related entries it declares itself
(users before groups and permissions, a filter before the user setting that names it, a task's
target, schedule and scan config before the task). Let the initial feed sync finish before
naming feed objects such as `Full and fast` or a port list. Run the first pass with
`puppet agent -t --noop`.

## Resource types and classes

| Type | Manages |
|---|---|
| `gvm_schedule` | Scan schedules (iCalendar) |
| `gvm_target` | Scan targets (hosts, port list, alive test) |
| `gvm_task` | Scan tasks (target, scan config, scanner, schedule) |
| `gvm_scan_config` | Scan configs cloned from a feed config, with managed preferences |
| `gvm_user` | GVM user accounts (local, LDAP or RADIUS) |
| `gvm_group`, `gvm_permission` | User groups and permissions, including `Super` for sharing |
| `gvm_user_setting` | Settings of the transport user (timezone, default filters) |
| `gvm_filter` | Saved filters |
| `gvm_override` | Severity overrides, e.g. assessed false positives |
| `gvm_ldap` | The `ldap_connect` authentication method (singleton) |

Classes: `greenbone` (transport file; repository, packages and directories in native mode),
`greenbone::resources` (the `gvm_*` resources from Hiera), `greenbone::ldap` (drives `gvm_ldap`)
and, for the native stack, `greenbone::database`, `greenbone::redis`, `greenbone::config`,
`greenbone::service`, `greenbone::admin`, `greenbone::feed` and the umbrella `greenbone::server`.
Every attribute and parameter is documented in
[REFERENCE.md](https://github.com/Data-JT/puppet-greenbone/blob/master/REFERENCE.md).

## Further documentation

- [Install methods](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/install-methods.md): docker versus native, the native stack order, the apt repository caveat.
- [Class parameters](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/class-parameters.md): the `greenbone` class, `user` versus `gvm_user`, the transport file.
- [The GMP account](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/gmp-account.md): which account the providers use, object ownership, sharing with other users.
- [LDAP authentication](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/ldap.md): `greenbone::ldap` and `gvm_ldap`, LDAP users.
- [Scan configs](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/scan-configs.md): cloning a feed config and managing scanner and NVT preferences.
- [Overrides](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/overrides.md): re-rating findings and marking false positives.
- [Resource notes](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/resource-notes.md): schedules, targets, tasks, users, settings, filters, groups and permissions in detail.
- [Clearing optional properties](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/clearing-properties.md): removing a value in gvmd with `delete_properties`.
- [Naming](https://github.com/Data-JT/puppet-greenbone/blob/master/docs/naming.md): the OpenVAS rebrand and why the module keeps the `greenbone` and `gvm_*` names.

## Limitations

- Docker mode is the tested path. The native install classes have unit tests but no production
  use, and the default apt repository (`https://dl.greenbone.net/repo/CE/stable`) is unverified.
- The agent must run on the Greenbone host with access to gvmd's Unix socket.
- `gvm_user` passwords are not compared: a changed password is only sent together with another
  attribute change, or when the user is recreated.
- A target used by a task cannot change its hosts, port list or lookup flags until the tasks are
  deleted (gvmd refuses with "Target is in use").
- `gvm_ldap` cannot clear a stored `cacert`; `gvm_override` supports neither task- or
  result-scoped nor time-limited overrides.
- `gvm_admin` passes the bootstrap password on the `gvmd` command line once, when it creates the
  account; rotate it afterwards.

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/Data-JT/puppet-greenbone/issues); please open an issue before
significant work. See [CONTRIBUTING.md](https://github.com/Data-JT/puppet-greenbone/blob/master/CONTRIBUTING.md)
for the development workflow and [SECURITY.md](https://github.com/Data-JT/puppet-greenbone/blob/master/SECURITY.md)
for reporting vulnerabilities.

## License

Apache-2.0, see [LICENSE](https://github.com/Data-JT/puppet-greenbone/blob/master/LICENSE).

## About Data JT

This module is built and maintained by [Data JT](https://www.data-jt.de), an IT and data
protection consultancy near Freiburg, Germany. All our modules are on the
[Puppet Forge](https://forge.puppet.com/modules/datajt). For anything beyond issues and pull
requests, [get in touch](https://www.data-jt.de/kontakt).
