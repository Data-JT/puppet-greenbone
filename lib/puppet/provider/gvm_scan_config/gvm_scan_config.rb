# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmScanConfig; end

# Provider for gvm_scan_config resources via the GMP Unix socket.
class Puppet::Provider::GvmScanConfig::GvmScanConfig < Puppet::Provider::GvmBaseProvider
  def get(context, names = nil)
    configs = list_configs(context)
    return [] unless configs

    wanted = names ? configs.select { |config| names.include?(config[:name]) } : configs
    wanted.map do |config|
      id, name = config.values_at(:id, :name)
      scanner, nvt = read_preferences(context, id)
      { ensure: 'present', name: name, scanner_preferences: scanner, nvt_preferences: nvt }
    end
  end

  # Subset semantics: the current state holds every preference of the config,
  # the manifest only the few it manages. Plain equality would be a permanent
  # diff, so only the listed preferences are compared.
  def insync?(context, title, property_name, is_hash, should_hash)
    drift = preference_drift(property_name, is_hash, should_hash)
    return super unless drift
    return [true, nil] if drift.empty?

    [false, describe(drift)]
  end

  def create(context, name, should)
    base = should[:base_config]
    context.notice("Creating GVM scan config '#{name}' from '#{base}'")
    reconcile(context, name, clone_config(context, name, base), should)
  end

  def update(context, name, should)
    id = config_id(context, name)
    raise Puppet::ResourceError, "GVM scan config not found for update: #{name}" unless id

    reconcile(context, name, id, should)
  end

  def delete(context, name)
    context.notice("Deleting GVM scan config '#{name}'")
    id = config_id(context, name)
    raise Puppet::ResourceError, "GVM scan config not found for delete: #{name}" unless id

    transport_command(context, "<delete_config config_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  # Drift of a preference property, or nil for every other property.
  def preference_drift(property_name, is_hash, should_hash)
    case property_name
    when :scanner_preferences
      scanner_drift(is_hash[:scanner_preferences] || {}, should_hash[:scanner_preferences] || {})
    when :nvt_preferences
      nvt_drift(index_nvt(is_hash[:nvt_preferences] || []), should_hash[:nvt_preferences] || [])
    end
  end

  # Clones the config named `base` as `config_name`; returns the new UUID.
  def clone_config(context, config_name, base)
    base_id = config_id(context, base)
    raise Puppet::ResourceError, "GVM base config '#{base}' not found; the feed may not be synced yet" unless base_id

    root = transport_command(context, "<create_config><copy>#{base_id}</copy><name>#{xe(config_name)}</name></create_config>")&.root
    checked_uuid(root&.attributes&.[]('id'), "new config '#{config_name}'")
  end

  # [{ id:, name: }] for every config, or nil when the transport is not
  # configured yet. rows=-1 because GMP pages list responses at ten rows, and
  # gvmd has more than ten configs out of the box (sixteen on 26.36).
  def list_configs(context)
    response = transport_command(context, '<get_configs filter="rows=-1"/>')
    return nil unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//config').map do |element|
      { id: element.attributes['id'], name: REXML::XPath.first(element, 'name')&.text.to_s }
    end
  end

  # UUID of the config named exactly `config_name`, or nil. More than one
  # config by that name is an error rather than a guess: tasks refer to
  # configs by name, and picking the wrong one would silently scan with other
  # preferences.
  def config_id(context, config_name)
    matches = (list_configs(context) || []).select { |config| config[:name] == config_name }
    count = matches.size
    raise Puppet::ResourceError, "#{count} GVM configs are named '#{config_name}'; refusing to guess which one is meant" if count > 1

    match = matches.first
    match && checked_uuid(match[:id], "config '#{config_name}'")
  end

  # Returns [scanner, nvt]: scanner as { name => value }, nvt as an array of
  # { 'oid', 'id', 'type', 'name', 'value' } in the shape the type declares.
  def read_preferences(context, id)
    response = transport_command(context, "<get_configs config_id=\"#{id}\" preferences=\"1\"/>")
    load_rexml_xpath
    config = response && REXML::XPath.first(response, '//config')
    raise Puppet::ResourceError, "GVM config #{id} disappeared while reading it" unless config

    scanner = {}
    nvt = []
    REXML::XPath.each(config, 'preferences/preference') do |pref|
      entry = parse_preference(pref)
      if entry['oid'].empty?
        scanner[entry['name']] = entry['value']
      else
        nvt << entry
      end
    end
    [scanner, nvt]
  end

  # String keys: the Resource API checks get() output against the type's
  # Struct, which has string keys, and rejects symbol ones.
  def parse_preference(pref)
    {
      # The OID is an ATTRIBUTE of <nvt>, not a child element, and scanner
      # preferences carry an <nvt oid=""> with it empty. Reading it as a child
      # yields nothing and makes every NVT preference look like a scanner one.
      'oid'   => REXML::XPath.first(pref, 'nvt')&.attributes&.[]('oid').to_s,
      'id'    => REXML::XPath.first(pref, 'id')&.text.to_s,
      'type'  => REXML::XPath.first(pref, 'type')&.text.to_s,
      'name'  => REXML::XPath.first(pref, 'name')&.text.to_s,
      'value' => REXML::XPath.first(pref, 'value')&.text.to_s,
    }
  end

  # `desired` is the resource's should hash; only its preferences are read.
  def reconcile(context, config_name, id, desired)
    drift = drift_of(context, id, desired)
    drift.each do |entry|
      context.notice("GVM scan config '#{config_name}': #{entry[:description]}")
      transport_command(context, "<modify_config config_id=\"#{id}\">#{entry[:fragment]}</modify_config>")
    end
    return if drift.empty?

    # Read back rather than trusting the 200s: modify_config answers OK for a
    # value it then stores as an empty string (see the type docs).
    remaining = drift_of(context, id, desired)
    return if remaining.empty?

    raise Puppet::ResourceError,
          "GVM scan config '#{config_name}': after writing, #{describe(remaining)} -- gvmd accepted the change but did not store it"
  end

  # The listed preferences that differ from what the config holds now.
  def drift_of(context, id, desired)
    scanner, nvt = read_preferences(context, id)
    scanner_drift(scanner, desired[:scanner_preferences] || {}) +
      nvt_drift(index_nvt(nvt), desired[:nvt_preferences] || [])
  end

  def describe(drift)
    drift.map { |entry| entry[:description] }.join('; ')
  end

  def scanner_drift(current, desired)
    desired.sort.filter_map do |pref, value|
      wanted = value.to_s
      actual = current[pref]
      next if actual == wanted

      {
        description: "scanner preference #{pref}: #{actual.inspect} -> #{wanted.inspect}",
        fragment:    "<preference><name>#{xe(pref)}</name><value>#{encoded(wanted)}</value></preference>",
      }
    end
  end

  def nvt_drift(current, desired)
    desired.filter_map do |entry|
      pref = entry.transform_keys(&:to_sym)
      oid, name = pref.values_at(:oid, :name)
      wanted = pref[:value].to_s
      actual = current[[oid, name]]
      next if actual == wanted

      # The write uses the qualified name; the plain one is a silent no-op.
      qualified = "#{oid}:#{pref[:id]}:#{pref[:type]}:#{name}"
      {
        description: "NVT preference '#{name}' (#{oid}): #{actual.inspect} -> #{wanted.inspect}",
        fragment:    "<preference><nvt oid=\"#{oid}\"/><name>#{xe(qualified)}</name><value>#{encoded(wanted)}</value></preference>",
      }
    end
  end

  # NVT preferences read back keyed by plain name, so (oid, name) identifies one.
  def index_nvt(entries)
    entries.to_h do |entry|
      pref = entry.transform_keys(&:to_sym)
      [pref.values_at(:oid, :name), pref[:value]]
    end
  end

  # Strict base64: pack('m0') needs no base64 gem, which is no longer a
  # default gem from Ruby 3.4.
  def encoded(value)
    [value.to_s].pack('m0')
  end
end
