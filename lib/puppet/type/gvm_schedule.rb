# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'gvm_schedule',
  features: ['custom_insync'],
  docs:  'Manages a GVM scan schedule defined by an iCalendar string.',

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this schedule should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Human-readable schedule name.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Human-readable description.',
    },
    icalendar: {
      type: 'String',
      desc: 'Full iCalendar (RFC 5545) string defining the schedule. Must contain at least one VEVENT with a DTSTART and RRULE.',
    },
    timezone: {
      type:    'String',
      desc:    'Timezone for the schedule (IANA tz database name).',
      default: 'UTC',
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment']]]",
      desc: 'Optional properties to clear on update, by attribute name. Removing an attribute from the manifest only stops Puppet managing it. Only `comment` can be cleared.',
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_schedule)
