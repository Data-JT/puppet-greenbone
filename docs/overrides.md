# Overrides

How `gvm_override` re-rates findings, most often to mark assessed false positives. All attributes
are documented in [REFERENCE.md](../REFERENCE.md#gvm_override).

An override rewrites the severity GVM reports for an NVT; `new_severity => -1` (the default) marks
the finding as a false positive.

```puppet
gvm_override { 'tcp-timestamps-false-positive':
  nvt_oid      => '1.3.6.1.4.1.25623.1.0.80091',
  new_severity => -1,
  hosts        => '192.0.2.10',
  text         => 'Assessed false positive: the kernel randomises per-connection TCP timestamp offsets.',
}
```

```yaml
greenbone::resources::overrides:
  tcp-timestamps-false-positive:
    nvt_oid: 1.3.6.1.4.1.25623.1.0.80091
    new_severity: -1
    hosts: 192.0.2.10
    text: 'Assessed false positive: the kernel randomises per-connection TCP timestamp offsets.'
```

Further attributes: `port`, `severity` (only rewrite results at this severity) and `active`
(boolean).

## Identity

A GVM override has no name, so the type appends a `[puppet:<title>]` marker line to the override
text and recovers the title from it. Overrides without the marker, such as ones created in the web
UI, are never read, changed or deleted. Renaming the title orphans the old override; set the old
title to `ensure => absent` for one run to remove it.

## Not supported

Task-scoped, result-scoped and time-limited overrides are not modelled. `hosts`, `port` and
`severity` cannot be cleared with `delete_properties`: the provider never sends them empty, and
how gvmd treats an omitted one on `modify_override` is unverified. Remove and re-create the
override instead.

Report pages apply overrides only when their filter says so; see the `Results Filter` example in
[Resource notes](resource-notes.md#gvm_user_setting).
