# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_permission',
  features: ['canonicalize', 'custom_insync'],
  docs:     <<~DOCS,
    Manages a GVM permission: the right named `permission` (a GMP command such
    as get_tasks, or Super), granted to a user, role or group (the subject),
    optionally limited to one named resource.

    THE NAMEVAR IS A PUPPET-SIDE FICTION, as for gvm_override. A permission's
    GMP `name` is the right it grants, not an identifier, so this type appends
    a `[puppet:<title>]` marker to the permission comment and recovers the
    title from it. Permissions without the marker -- the ~270 built-in ones
    and any made in the web UI -- are never read, changed or deleted.

    The common use is Super, which makes every object the resource's users own
    visible and editable to the subject. gvmd only accepts Super on a resource
    the creating user owns, and requires a resource (Super on everyone is
    the Super Admin role, which GMP cannot assign). To share the transport
    user's objects, grant Super on a gvm_group that contains the transport
    user; see gvm_group for why the user itself does not work.

    Subjects and resources are referenced by NAME and resolved to UUIDs on
    write, so only named resource types work (user, role, group, task,
    target, config, ...); a report has no name and cannot be addressed here.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this permission should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Puppet-side identifier, stored as a [puppet:<name>] marker in the comment. Renaming orphans the old permission; ensure => absent it for one run first.',
      behaviour: :namevar,
    },
    permission: {
      type: 'Pattern[/\A[A-Za-z_]+\z/]',
      desc: 'The right granted: a GMP command name (get_tasks, modify_target, ...) or "Super". gvmd lower-cases command names and writes Super as "Super"; this type does the same so they compare.',
    },
    subject_type: {
      type: 'Enum[user, role, group]',
      desc: 'Kind of subject the permission is granted to.',
    },
    subject_name: {
      type: 'String',
      desc: 'Name of the subject user, role or group.',
    },
    resource_type: {
      type: 'Optional[Pattern[/\A[a-z_]+\z/]]',
      desc: 'Type of the resource the permission is limited to. For Super it must be user, role or group. Undef grants the right on every resource of its kind (not allowed for Super).',
    },
    resource_name: {
      type: 'Optional[String]',
      desc: 'Name of that resource. Set together with resource_type.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Why the permission exists. The marker is appended after it. Leading and trailing whitespace is stripped.',
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment']]]",
      desc: <<~DESC,
        Optional properties to clear on update, by attribute name. Removing an
        attribute from the manifest only stops Puppet managing it. Only `comment`
        can be cleared: the provider omits an unset resource, and whether
        modify_permission then drops the stored one is unverified, so to remove
        resource_type and resource_name, replace the permission.
      DESC
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_permission)
