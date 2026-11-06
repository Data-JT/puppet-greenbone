# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

# Manages a GVM setting for the transport-authenticated user (typically admin).
# The title is the setting name as returned by GMP get_settings.
#
# GMP settings are key/value pairs stored per-user. Common names:
#   'Default Severity'            (e.g. '0.0')
#   'Default Alert'               (UUID of an alert object, or empty)
#   'Default OpenVAS Scanner'     (UUID)
#   'Default Port List'           (UUID)
#   'Default Scan Config'         (UUID)
#   'Auto Cache Rebuild'          ('1' or '0')
#   'User Interface Language'     ('en', 'de', etc.)
#   'Timezone'                    ('Europe/Berlin', etc.)
#   'Max Rows Per Page'           (integer as string)
#   'Results Filter'              (default filter of the result views; use
#                                  filter_name, plus setting_id -- see below)
Puppet::ResourceApi.register_type(
  name:  'gvm_user_setting',
  docs:  'Manages a GVM user setting for the transport-authenticated user.',

  attributes: {
    ensure: {
      # resource_api requires ensure to be Enum[present, absent]. GMP settings
      # cannot actually be deleted, so the provider's delete raises a clear
      # error if absent is ever requested; in practice always use present.
      type:    'Enum[present, absent]',
      desc:    'Whether this setting should exist. GMP settings cannot be deleted, so absent is rejected by the provider — always use present.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Setting name as returned by GMP get_settings.',
      behaviour: :namevar,
    },
    value: {
      type: 'Optional[String]',
      desc: 'Setting value. Pass a UUID string for object-reference settings. Exactly one of value and filter_name must be set.',
    },
    filter_name: {
      type: 'Optional[String]',
      desc: <<~DESC,
        Name of a saved filter (e.g. a gvm_filter) to point this setting at, for
        the web UI's default-filter settings such as 'Results Filter'. Resolved
        to the filter's UUID on write and compared by name on read, so the
        manifest never has to carry a UUID gvmd assigns. A gvm_filter of that
        name declared through greenbone::resources is ordered before it.
      DESC
    },
    setting_id: {
      type:      'Optional[Pattern[/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/]]',
      desc:      <<~DESC,
        UUID of the setting. Only needed for a setting gvmd does not list until it
        has been written once -- the web UI's default-filter settings are like
        that (verified 2026-10-20: 'Results Filter', 739ab810-163d-11e3-9af6-406186ea4fc5,
        was absent from get_settings, even when asked for by id, until set).
        Without it such a setting fails with "GVM setting not found".
      DESC
      behaviour: :parameter,
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_user_setting)
