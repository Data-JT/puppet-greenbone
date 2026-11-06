# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_group',
  features: ['canonicalize', 'custom_insync'],
  docs:     <<~DOCS,
    Manages a GVM user group, matched by name. The group is owned by the
    transport user.

    The reason this type exists is Super permissions (see gvm_permission):
    gvmd only lets a user grant Super on a resource it OWNS, and the
    transport user owns neither its own user record nor any built-in role
    (users.owner and roles.owner are NULL; measured on gvmd 26.42,
    2026-10-20 -- "Super on user admin" is refused with "Permission
    denied"). A group the transport user creates IS owned by it, and gvmd's
    ACL honours "Super on a group the other user is a member of", so a group
    holding the transport user is the resource to grant Super on.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this group should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Group name.',
      behaviour: :namevar,
    },
    users: {
      type:    'Array[String]',
      desc:    'Member user names, compared as a set (order and duplicates ignored). gvmd stores them as one comma-separated list.',
      default: [],
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Free-text comment shown in the web UI.',
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment']]]",
      desc: 'Optional properties to clear on update, by attribute name. Removing an attribute from the manifest only stops Puppet managing it. Only `comment` can be cleared.',
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_group)
