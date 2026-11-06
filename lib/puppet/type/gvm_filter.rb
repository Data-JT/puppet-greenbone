# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_filter',
  features: ['canonicalize', 'custom_insync'],
  docs:     <<~DOCS,
    Manages a saved GVM filter -- the named filter objects the web UI offers
    in its filter dropdowns, and the thing a default-filter user setting points
    at. Point a gvm_user_setting at one with `filter_name` to make it the
    default for a page, e.g. 'Results Filter' for the report results view.

    gvmd REWRITES THE TERM on create and modify, and this type canonicalizes
    the manifest's term the same way so it does not churn. Measured against
    gvmd 26.42 on 2026-10-20:

      * runs of whitespace collapse to one space;
      * a missing `first=`, `rows=` or `sort=`/`sort-reverse=` keyword is
        appended as `first=1`, `rows=10`, `sort=name`, in that order;
      * `rows=-1` is replaced by the user's Max Rows Per Page value.

    The first two are reproduced here. The third depends on another setting,
    so `rows=-1` is rejected instead -- write the row count you want.

    Filters are matched by name. A filter made by hand in the web UI with the
    same name is adopted; any other hand-made filter is never touched.
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this filter should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Filter name. gvmd rejects a second filter of the same name for the same owner.',
      behaviour: :namevar,
    },
    filter_type: {
      type:    'Pattern[/\A[a-z_]+\z/]',
      desc:    'GMP filter type, i.e. which kind of list it filters: result, report, task, target, override, ... Defaults to result.',
      default: 'result',
    },
    term: {
      type: 'String',
      desc: 'The filter term, e.g. "apply_overrides=1 levels=chml rows=100 min_qod=70 first=1 sort-reverse=severity". Canonicalized as gvmd stores it; see the type docs.',
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

Puppet::Type::GvmTransportAutorequire.register(:gvm_filter)
