# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'gvm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'gvm_scan_config',
  features: ['custom_insync', 'simple_get_filter'],
  docs:     <<~DOCS,
    Manages a GVM scan config cloned from a feed config, and the scanner and NVT
    preferences set on it.

    WHY A CLONE: preferences can only be set on a config you own. The feed's
    configs ("Full and fast" and friends) are not writable and modify_config
    answers 400 on them. This type clones `base_config` once, under `name`, and
    reconciles preferences onto the clone. A clone keeps the base's dynamic NVT
    family selection, so it still picks up new checks as the feed grows.

    PREFERENCES ARE A SUBSET, NOT THE WHOLE CONFIG. Only the preferences listed
    in `scanner_preferences` and `nvt_preferences` are managed; every other
    preference of the config (there are well over a thousand) is left as it is.
    A listed preference changed in the web UI is set back on the next run.

    GMP FACTS THIS TYPE IS BUILT ON (measured against gvmd 26.36):

      * Preference VALUES are base64-encoded on write. A bare value is accepted
        with a 200, stored as an empty string, and reads back as unset.
      * An NVT preference is WRITTEN under its qualified name
        "<oid>:<id>:<type>:<name>" -- the plain name is accepted with a 200 and
        silently stores the feed default -- but READ BACK under its plain name,
        with the OID as an attribute of <nvt>. That is why each
        `nvt_preferences` entry needs all five keys.
      * Because a 200 proves nothing here, every write is read back, and a
        value that does not read back as written fails the resource.

    Renaming a config does not rename the clone: a new one is created under
    the new name. Note that gvmd refuses to re-point a task that has already
    run ("Status must be New to edit config").
  DOCS

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this scan config should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'Name of the scan config. gvm_task refers to it by this name as config_name.',
      behaviour: :namevar,
    },
    base_config: {
      type:      'String',
      desc:      'Name of the config to clone when this one does not exist yet, e.g. "Full and fast". Read only at creation; it must exist, i.e. the feed must have synced.',
      default:   'Full and fast',
      behaviour: :parameter,
    },
    scanner_preferences: {
      type:    'Hash[String, String]',
      desc:    'Scanner preferences to enforce, by name, e.g. { "expand_vhosts" => "0" }. Values are strings, as GMP stores them.',
      default: {},
    },
    nvt_preferences: {
      type:    'Array[Struct[{ oid => Pattern[/\A[0-9]+(\.[0-9]+)*\z/], id => String, type => String, name => String, value => String }]]',
      desc:    <<~DESC,
        NVT preferences to enforce. `id` and `type` come from the VT's own
        preference definition (get_nvts); all five keys are needed, see the type
        docs. The OID is pattern-constrained because it is interpolated into a GMP
        XML attribute.
      DESC
      default: [],
    },
  },
)

Puppet::Type::GvmTransportAutorequire.register(:gvm_scan_config)
