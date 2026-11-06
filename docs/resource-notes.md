# Resource notes

Behaviour of the `gvm_*` types that is not obvious from their attribute lists. The attributes
themselves are documented in [REFERENCE.md](../REFERENCE.md). Scan configs, overrides and LDAP
have pages of their own: [Scan configs](scan-configs.md), [Overrides](overrides.md),
[LDAP authentication](ldap.md).

All `gvm_*` types match objects by name, except `gvm_override` and `gvm_permission`, which carry a
`[puppet:<title>]` marker. Every object is owned by the transport user; see
[The GMP account](gmp-account.md).

| Type | GMP commands |
|---|---|
| `gvm_schedule` | `create_schedule` / `modify_schedule` / `delete_schedule` |
| `gvm_target` | `create_target` / `modify_target` / `delete_target` |
| `gvm_task` | `create_task` / `modify_task` / `delete_task` |
| `gvm_scan_config` | `create_config` (clone) / `modify_config` / `delete_config` |
| `gvm_user` | `create_user` / `modify_user` / `delete_user` |
| `gvm_user_setting` | `modify_setting` |
| `gvm_filter` | `create_filter` / `modify_filter` / `delete_filter` |
| `gvm_group` | `create_group` / `modify_group` / `delete_group` |
| `gvm_permission` | `create_permission` / `modify_permission` / `delete_permission` |
| `gvm_override` | `create_override` / `modify_override` / `delete_override` |
| `gvm_ldap` | `describe_auth` / `modify_auth` |

## gvm_schedule

A schedule defined by an iCalendar (RFC 5545) string with at least one `VEVENT` holding a
`DTSTART` and an `RRULE`, plus a `timezone` (IANA name, default `UTC`).

```puppet
gvm_schedule { 'Weekly Monday 02:00':
  icalendar => @(ICAL),
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Puppet Greenbone Profile//EN
    BEGIN:VEVENT
    DTSTART:20260105T020000
    RRULE:FREQ=WEEKLY;BYDAY=MO
    END:VEVENT
    END:VCALENDAR
    | ICAL
  timezone  => 'Europe/Berlin',
}
```

gvmd rewrites the calendar on save: it replaces `PRODID`, adds `UID`, `DTSTAMP` and
`DURATION:PT0S`, and drops `SUMMARY`. The provider normalises the stored calendar back, so write
the manifest value with `PRODID:-//Puppet Greenbone Profile//EN`, without `UID`, `DTSTAMP` and
`SUMMARY`, and ending in a newline, as above.

## gvm_target

```puppet
gvm_target { 'internal-servers':
  hosts          => '198.51.100.0/24, 203.0.113.0/24',
  exclude_hosts  => '198.51.100.5',
  port_list_name => 'All IANA assigned TCP',
  alive_test     => 'ICMP Ping',
  comment        => 'Internal server subnets',
}
```

`hosts` and `exclude_hosts` are canonicalised the way gvmd stores them (`"a, b"`), so a list
written without spaces does not churn. Updates send only the attributes that differ: on a target
that a task uses, gvmd refuses `hosts`, `exclude_hosts`, the port list and the three boolean flags
(`allow_simultaneous_ips`, `reverse_lookup_only`, `reverse_lookup_unify`) as soon as they appear in
the request, changed or not. A real change to one of them still fails with "Target is in use"
until the tasks using the target are deleted.

## gvm_task

References a target, scan config, scanner and optional schedule by name; the provider resolves the
names to IDs.

```puppet
gvm_task { 'weekly-internal':
  target_name    => 'internal-servers',
  config_name    => 'Full and fast',
  scanner_name   => 'OpenVAS Default',
  schedule_name  => 'Weekly Monday 02:00',
  hosts_ordering => 'random',
  require        => [Gvm_target['internal-servers'], Gvm_schedule['Weekly Monday 02:00']],
}
```

Further attributes: `comment`, `alterable`, `auto_delete`, `auto_delete_data`, `max_concurrency`
and `max_hosts`. The `require` is only needed outside `greenbone::resources`, which orders a task's
target, schedule and scan config before the task itself.

## gvm_user

```puppet
gvm_user { 'alice':
  password  => Sensitive(lookup('greenbone::users::alice::password')),
  role_name => 'User',
}
```

`source` selects the authentication backend: `file` (default, local password), `ldap_connect`, or
`radius_connect`. `hosts` and `hosts_allow` restrict which hosts the user may access.

The password is write-only: it is sent on create and on every update, but GMP never returns it, so
it is never compared. Changing only the password does not trigger an update. A password on an
`ldap_connect` or `radius_connect` user is refused: gvmd would store it as a local hash that starts
working whenever LDAP is switched off.

## gvm_user_setting

Manages settings of the transport user (the class parameter `user`). Values are base64-encoded on
write, as gvmd requires; write them plain here.

```puppet
gvm_user_setting { 'Timezone':
  value => 'Europe/Berlin',
}

gvm_user_setting { 'Max Rows Per Page':
  value => '100',
}
```

A setting gvmd does not list until it has been written once (the web UI's default-filter settings
are like that) needs its `setting_id`. Point a default-filter setting at a saved filter by name
with `filter_name`:

```puppet
gvm_filter { 'Results (overrides applied)':
  term => 'apply_overrides=1 levels=chml rows=100 min_qod=70 first=1 sort-reverse=severity',
}

gvm_user_setting { 'Results Filter':
  filter_name => 'Results (overrides applied)',
  setting_id  => '739ab810-163d-11e3-9af6-406186ea4fc5',
  require     => Gvm_filter['Results (overrides applied)'],
}
```

`Results Filter` is what the report details page falls back to when its URL carries no filter.
Without it the page uses GSA's built-in default, which gvmd completes with `apply_overrides=0`.

## gvm_filter

A saved filter, matched by name. gvmd rewrites the term on write (whitespace collapsed, missing
`first=1`, `rows=10`, `sort=name` appended), and the type canonicalises the manifest's term the
same way. `rows=-1` is rejected, because gvmd stores it as the Max Rows Per Page value.
`filter_type` defaults to `result`.

## gvm_group and gvm_permission

`gvm_group` is a user group, matched by name, with `users` compared as a set. Its main use is as
the resource of a `Super` permission.

`gvm_permission` is a permission granted to a user, role or group, optionally on one named
resource. It is identified by a `[puppet:<title>]` marker in its comment, like `gvm_override`; the
built-in permissions and hand-made ones are never touched. The sharing pattern (Super on a group
holding the transport user) is described in [The GMP account](gmp-account.md#sharing-with-other-users).

## Ordering in greenbone::resources

The resources class orders related entries declared in its Hiera hashes: users before groups, users
and groups before permissions, a filter before the user setting that names it, and a task's
target, schedule and scan config before the task. References to resources not declared through
this class are left unconstrained.
