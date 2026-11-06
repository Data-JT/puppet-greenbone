# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_target',
  features: ['canonicalize', 'custom_insync'],
  docs:     <<~DOCS,
    Manages a GVM scan target.

    gvmd locks hosts, exclude_hosts, port_list_name and the three flags on a
    target that any task references ("Target is in use"); only comment and
    alive_test can change then. The provider sends only the attributes that
    differ, so a locked attribute fails only when it really changes.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this scan target should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Unique name of the scan target.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Human-readable description.',
    },
    hosts: {
      type: 'String',
      desc: 'Comma-separated list of hosts, CIDRs, or ranges to scan.',
    },
    exclude_hosts: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of hosts to exclude from the scan.',
    },
    port_list_name: {
      type:    'String',
      desc:    'Name of the GVM port list to use (e.g. "All IANA assigned TCP").',
      default: 'All IANA assigned TCP',
    },
    alive_test: {
      # One literal on one line: puppet-strings documents neither a
      # concatenated type nor a heredoc one (it keeps the indentation).
      type: 'Optional[Enum["Scan Config Default","ICMP Ping","TCP-ACK Service Ping","TCP-SYN Service Ping","ARP Ping","ICMP & TCP-ACK Service Ping","ICMP & ARP Ping","TCP-ACK Service & ARP Ping","ICMP, TCP-ACK Service & ARP Ping","Consider Alive"]]', # rubocop:disable Layout/LineLength
      desc: 'Host alive detection method.',
    },
    allow_simultaneous_ips: {
      type:    'Boolean',
      desc:    'Whether to scan all IPs of a host simultaneously.',
      default: true,
    },
    reverse_lookup_only: {
      type:    'Boolean',
      desc:    'Scan only hosts that resolve to a hostname.',
      default: false,
    },
    reverse_lookup_unify: {
      type:    'Boolean',
      desc:    'Deduplicate hosts that resolve to the same IP.',
      default: false,
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment', 'exclude_hosts']]]",
      desc: <<~DESC,
        Optional properties to clear on update, by attribute name. Removing an
        attribute from the manifest only stops Puppet managing it. `comment` and
        `exclude_hosts` can be cleared. gvmd refuses an exclude_hosts change on a
        target a task references, so clearing it fails then, like any other change
        to it. alive_test cannot be unset; set it to 'Scan Config Default' instead.
      DESC
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_target)
