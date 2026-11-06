# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Dependency ranges now include the first releases that allow Puppet 9 (`puppetlabs/stdlib`
  10.x, `puppetlabs/apt` 11.x), so the module installs on Puppet 9 as `metadata.json` claims.

### Changed

- The Quality workflow also runs the unit tests on OpenVox 9.
- Data JT banner and an About section in the README; `metadata.json` names Data JT as the
  author.

## [0.1.0] - 2026-11-06

Initial release.

### Added

- Supports Puppet 8 and 9 (tested on 8) on Debian 12 and 13. Docker mode (Greenbone Community
  Containers) is the tested path; the native apt install path is untested.
- `greenbone` class that writes the GMP transport credentials (`user`, `password`, `socket`)
  to `<agent confdir>/gvm_transport.yaml`, `root:root` mode `0600`. The agent's confdir comes
  from the new `greenbone_confdir` fact. With `install_method => 'unmanaged'` (the default) it
  also manages the apt repository, packages, the `gvm` system account and runtime directories;
  with `install_method => 'docker'` it manages only the transport file.
- Classes for a native stack: `greenbone::database` (PostgreSQL role, database, `pg-gvm`,
  `gvmd --migrate`), `greenbone::redis`, `greenbone::config`, `greenbone::service`,
  `greenbone::admin`, `greenbone::feed` (systemd timer and initial sync), and
  `greenbone::server`, which contains and orders all of them.
- `greenbone::ldap` for gvmd's LDAP authentication, and `greenbone::resources`, which declares
  `gvm_*` resources from Hiera hashes and orders related entries.
- Resource types managed over the GMP Unix socket: `gvm_schedule`, `gvm_target`, `gvm_task`,
  `gvm_scan_config`, `gvm_user`, `gvm_user_setting`, `gvm_filter`, `gvm_group`,
  `gvm_permission`, `gvm_override` and `gvm_ldap`, plus `gvm_admin`, which creates the initial
  admin account with the `gvmd` command line.
- `gvm_override` and `gvm_permission` identify their objects by a `[puppet:<title>]` marker, so
  objects created by hand are never touched.
- `gvm_scan_config` clones a feed config and manages only the listed scanner and NVT
  preferences, reading every write back.
- `gvm_target`, `gvm_filter` and `gvm_schedule` normalise values the way gvmd stores them,
  so declared values do not churn; `gvm_target` updates send only the attributes that differ.
- `gvm_user_setting` accepts `filter_name` and `setting_id` for the web UI's default-filter
  settings.
- `gvm_user` refuses a password on an LDAP or RADIUS user, and its password is redacted
  wherever Puppet formats it, also when it is given as a plain String.
- `delete_properties` clears optional properties on `gvm_filter`, `gvm_group`,
  `gvm_permission`, `gvm_schedule`, `gvm_target`, `gvm_task` and `gvm_user`.
- Path, socket, URL and account parameters of the classes are type-checked (absolute paths,
  http(s) URLs, non-empty account names).

[Unreleased]: https://github.com/Data-JT/puppet-greenbone/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Data-JT/puppet-greenbone/releases/tag/v0.1.0
