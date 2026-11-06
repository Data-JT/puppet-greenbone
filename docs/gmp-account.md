# The GMP account

Which GVM account the providers use, what that means for ownership, and how to share the managed
objects with other users.

## Choosing the account

The providers log in to gvmd as one GVM account, `admin` by default (class parameter `user`), with
the password from `greenbone::password`. A local (`file`) account is recommended: it keeps working
while an LDAP server is unreachable. In the native stack, `greenbone::admin` creates the `admin`
account; in docker mode, use the account the container stack created, or create a dedicated one
in the web UI first.

The account needs the rights to create and modify the objects you declare; the `Admin` role covers
everything the module manages, including the `gvm_ldap` singleton and `gvm_user`.

## Ownership

Every object the providers create is owned by the transport user. `gvm_user_setting` manages the
settings of that same account. Other users do not see those objects by default, which matters
once people log in through LDAP.

## Sharing with other users

To let another user see and edit the objects this module creates, grant them `Super` on a group
holding the transport user. `Super` on the transport user itself is refused: gvmd only accepts
`Super` on a resource the granting user owns, and the transport user does not own its own user
record.

```puppet
gvm_user { 'alice':
  role_name => 'Admin',
  source    => 'ldap_connect',
}

gvm_group { 'Shared by admin':
  users => ['admin'],
}

gvm_permission { 'alice-super-on-admin':
  permission    => 'Super',
  subject_type  => 'user',
  subject_name  => 'alice',
  resource_type => 'group',
  resource_name => 'Shared by admin',
  comment       => 'alice works with the scans Puppet manages as admin.',
}
```

The same in Hiera:

```yaml
greenbone::resources::users:
  alice:
    role_name: Admin
    source: ldap_connect

greenbone::resources::groups:
  'Shared by admin':
    users: ['admin']

greenbone::resources::permissions:
  alice-super-on-admin:
    permission: Super
    subject_type: user
    subject_name: alice
    resource_type: group
    resource_name: Shared by admin
```

`gvm_permission` identifies its permissions by a `[puppet:<title>]` marker in the comment, so the
built-in permissions and ones made by hand are never touched. See
[Resource notes](resource-notes.md#gvm_group-and-gvm_permission).
