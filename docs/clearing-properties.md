# Clearing optional properties

How to remove a value in gvmd, since removing an attribute from a manifest does not.

Removing an attribute from a manifest only stops Puppet comparing it, so the removal alone never
changes anything in gvmd. To clear an optional property, list its attribute name in
`delete_properties`:

```puppet
gvm_target { 'Office network':
  hosts             => '192.0.2.0/24',
  delete_properties => ['comment', 'exclude_hosts'],
}
```

GMP has no delete parameter, so the provider sends the element empty on update, which is how it
already writes an unset value. It does so only while one of the named properties is still set, so
the resource converges instead of re-sending the change on every run. Declaring a value for an
attribute that is also listed fails the resource, because it could never converge. Create requests
never need it.

Each type accepts only the attributes its provider can clear:

| Type | Clearable attributes |
|---|---|
| `gvm_filter` | `comment` |
| `gvm_group` | `comment` |
| `gvm_permission` | `comment` (the `[puppet:<title>]` marker stays) |
| `gvm_schedule` | `comment` |
| `gvm_target` | `comment`, `exclude_hosts` |
| `gvm_task` | `comment`, `schedule_name` |
| `gvm_user` | `hosts` |

Some providers write the whole object on update, so a few undeclared attributes are cleared the
next time another attribute of the same resource changes: `comment` on `gvm_filter`, `gvm_group`
and `gvm_permission`, `hosts` on `gvm_user`, `schedule_name` on `gvm_task` and `exclude_hosts` on
`gvm_target`. Declare them to keep a value set outside Puppet.

## Not clearable

- `gvm_target`'s `alive_test`: set it to `'Scan Config Default'` instead. Clearing `exclude_hosts`
  on a target a task references fails like any other change to it.
- `gvm_task`'s `max_concurrency` and `max_hosts`: an omitted preference keeps the value gvmd
  stores.
- `gvm_permission`'s `resource_type` and `resource_name`: replace the permission.
- `gvm_override`'s `hosts`, `port` and `severity`: the provider never sends them empty, and how
  gvmd treats an omitted one on `modify_override` is unverified.
- `gvm_ldap`'s `cacert`: gvmd rejects an empty certificate.
