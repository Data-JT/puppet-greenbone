# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_override',
  features: ['canonicalize'],
  docs:     <<~DOCS,
    Manages a GVM override: a rule that rewrites the severity GVM reports for a
    given NVT, so a finding you have assessed and accepted stops colouring
    every report. The common case is marking an assessed false positive, which
    is `new_severity => -1`.

    THE NAMEVAR IS A PUPPET-SIDE FICTION. A GVM override has no name -- GMP
    identifies it by UUID alone, and `get_overrides` returns no name element
    (verified against gvmd 26.37 on 2026-09-07). To make an override
    addressable across runs, this type appends a marker line to the override's
    text:

        <your text>

        [puppet:<resource title>]

    and the provider recovers the title from it. Two consequences worth
    knowing before using this type:

      * The marker is visible in the GVM web UI. That is deliberate -- an
        auditor reading an override sees which Puppet resource put it there.
      * An override WITHOUT the marker is invisible to this type. Overrides
        created by hand in the web UI are never read, updated or deleted by
        Puppet, and `puppet resource gvm_override` will not list them. Renaming
        the resource title orphans the old override rather than renaming it;
        set the old title to `ensure => absent` for one run to clean it up.

    NOT SUPPORTED, deliberately: task- and result-scoped overrides, and
    time-limited ones (GMP's `active` taking a day count). `active` here is a
    boolean. All three are additive if they are ever needed; they were left out
    because their GMP round-trip shape was not verified and an unverified
    round-trip in a provider is what produces silent per-run churn.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this override should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Puppet-side identifier. Stored as a `[puppet:<name>]` marker in the override text; see the type docs.',
      behaviour: :namevar,
    },
    nvt_oid: {
      type: 'Pattern[/\A[0-9]+(\.[0-9]+)*\z/]',
      desc: 'OID of the NVT this override applies to, e.g. 1.3.6.1.4.1.25623.1.0.80091. Pattern-constrained because it is interpolated into a GMP XML attribute.',
    },
    text: {
      type: 'String',
      desc: 'Justification for the override. This is the audit trail -- say what was assessed and on what evidence. Leading and trailing whitespace is stripped so a YAML block scalar does not churn.',
    },
    hosts: {
      type: 'Optional[String]',
      desc: 'Comma-separated hosts/CIDRs this override is limited to. Undef applies it to every host. Whitespace around commas is normalized.',
    },
    port: {
      type: 'Optional[String]',
      desc: 'Port this override is limited to, in GVM notation, e.g. "general/tcp". Undef applies it to every port.',
    },
    severity: {
      type: 'Optional[Numeric]',
      desc: 'Only rewrite results whose current severity is this value. Undef applies the override at any severity.',
    },
    # No `default:` key: puppet-strings cannot parse a negative literal and
    # would drop the whole type from REFERENCE.md. The provider's canonicalize
    # fills in -1 when the attribute is not declared, which has the same
    # effect as a schema default.
    new_severity: {
      type: 'Numeric',
      desc: 'Severity to report instead. -1 is False Positive, 0 is Log; a positive value re-rates rather than clears. Defaults to -1 when not declared.',
    },
    active: {
      type:    'Boolean',
      desc:    'Whether the override is in effect. Maps to GMP active -1/0; time-limited overrides are not supported.',
      default: true,
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_override)
