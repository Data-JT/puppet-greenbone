# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'gvm_task',
  features: ['custom_insync'],
  docs:  'Manages a GVM scan task.',

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this scan task should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Unique name of the scan task.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Human-readable description.',
    },
    target_name: {
      type: 'String',
      desc: 'Name of the GVM scan target to scan.',
    },
    config_name: {
      type:    'String',
      desc:    'Name of the scan config to use (e.g. "Full and fast").',
      default: 'Full and fast',
    },
    scanner_name: {
      type:    'String',
      desc:    'Name of the scanner to use.',
      default: 'OpenVAS Default',
    },
    schedule_name: {
      type: 'Optional[String]',
      desc: 'Name of a GVM schedule. Unset means the task runs on demand only.',
    },
    alterable: {
      type:    'Boolean',
      desc:    'Whether the task can be modified while running.',
      default: false,
    },
    auto_delete: {
      type:    'Boolean',
      desc:    'When true, gvmd keeps only auto_delete_data most-recent reports and deletes older ones automatically. When false, all reports are kept.',
      default: false,
    },
    auto_delete_data: {
      type:    'Integer[2, 1200]',
      desc:    <<~DESC,
        Number of most-recent reports to keep when auto_delete is true (gvmd valid
        range: 2–1200). Ignored when auto_delete is false. Note: gvmd does not
        expose an API to reset this value to the "off" internal state (0) once set;
        to disable auto_delete on a task that previously had it enabled, delete and
        recreate the task.
      DESC
      default: 5,
    },
    hosts_ordering: {
      type:    'Enum["sequential","random","reverse"]',
      desc:    <<~DESC,
        Order in which target hosts are scanned. Note: gvmd silently ignores this
        value in modify_task and always returns "sequential" — "random"/"reverse"
        take effect at task creation only and cause perpetual Puppet drift
        thereafter. Leave at the default "sequential" unless creating a brand-new
        task and accepting the drift.
      DESC
      default: 'sequential',
    },
    max_concurrency: {
      type: 'Optional[Integer]',
      desc: <<~DESC,
        Maximum number of concurrently executed NVTs per host (the openvas
        "max_checks" scanner preference; scanner default is 10). Lower this to
        reduce CPU load per host at the cost of a slower scan.
      DESC
    },
    max_hosts: {
      type: 'Optional[Integer]',
      desc: <<~DESC,
        Maximum number of target hosts scanned simultaneously (the openvas
        "max_hosts" scanner preference; scanner default is 30). This is the dominant
        load lever: total peak concurrency is roughly max_hosts * max_concurrency.
        Lower it to keep the scanner from saturating the host.
      DESC
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment', 'schedule_name']]]",
      desc: <<~DESC,
        Optional properties to clear on update, by attribute name. Removing an
        attribute from the manifest only stops Puppet managing it. `comment` and
        `schedule_name` can be cleared; clearing schedule_name makes the task run on
        demand only. max_concurrency and max_hosts cannot be cleared: the provider
        omits an unset preference and gvmd keeps the stored value.
      DESC
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_task)
