# Scan configs

How `gvm_scan_config` derives a tuned scan config from a feed config. All attributes are documented
in [REFERENCE.md](../REFERENCE.md#gvm_scan_config).

The feed's own scan configs (`Full and fast`, `Base`, …) are not writable. `gvm_scan_config` clones
`base_config` once and enforces the listed preferences on the clone. Only the listed preferences
are managed; every other preference of the config is left alone. Every write is read back, because
gvmd answers 200 to writes it silently drops.

```puppet
gvm_scan_config { 'Full and fast (tuned)':
  base_config         => 'Full and fast',
  scanner_preferences => { 'expand_vhosts' => '0' },
  nvt_preferences     => [{
    'oid'   => '1.3.6.1.4.1.25623.1.0.12288',
    'id'    => '18',
    'type'  => 'checkbox',
    'name'  => 'Disable caching of web pages during CGI scanning',
    'value' => 'yes',
  }],
}
```

```yaml
greenbone::resources::scan_configs:
  'Full and fast (tuned)':
    base_config: Full and fast
    scanner_preferences:
      expand_vhosts: '0'
    nvt_preferences:
      - oid: 1.3.6.1.4.1.25623.1.0.12288
        id: '18'
        type: checkbox
        name: Disable caching of web pages during CGI scanning
        value: 'yes'
```

## Preferences

- `scanner_preferences` is a hash of scanner preference name to value, as strings.
- An NVT preference needs all five keys: gvmd writes it under the qualified name
  `<oid>:<id>:<type>:<name>` and accepts the plain name with a 200 while storing nothing. `id` and
  `type` come from the VT's preference definition (`get_nvts` in GMP, or the preference's details
  in the web UI).
- Quote values that YAML would otherwise type (`'0'`, `'yes'`): gvmd compares strings.

## Using the config

Reference the clone by name from a task, and let the initial feed sync finish before the first
run, since the base config has to exist:

```yaml
greenbone::resources::tasks:
  weekly-internal:
    target_name: internal-servers
    config_name: 'Full and fast (tuned)'
    scanner_name: OpenVAS Default
```

The resources class orders a task's scan config before the task when both are declared through it.
