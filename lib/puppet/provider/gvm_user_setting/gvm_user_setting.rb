# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmUserSetting; end

# Provider for gvm_user_setting resources via the GMP Unix socket.
#
# Settings are managed for the user the transport authenticates as.
# GMP does not support modifying another user's settings as admin.
class Puppet::Provider::GvmUserSetting::GvmUserSetting < Puppet::Provider::GvmBaseProvider
  def get(context)
    response = transport_command(context, '<get_settings/>')
    return [] unless response

    load_rexml_xpath
    @setting_ids = setting_ids_in(response)
    filter_names = nil
    REXML::XPath.match(response, '//setting').map do |element|
      value = REXML::XPath.first(element, 'value')&.text.to_s
      # filter_name is reported for every setting whose value is a filter's
      # UUID, so a manifest that names the filter compares by name. Fetched
      # once, and only when some value looks like a UUID at all.
      filter_names ||= fetch_filter_names(context) if value.match?(UUID_PATTERN)
      {
        ensure:      'present',
        name:        REXML::XPath.first(element, 'name')&.text,
        value:       value,
        filter_name: filter_names&.[](value),
      }
    end
  end

  def create(context, name, should)
    update(context, name, should)
  end

  def update(context, name, should)
    context.notice("Updating GVM user setting '#{name}'")
    id = should[:setting_id] || setting_id(context, name)
    raise Puppet::ResourceError, "GVM setting not found: #{name} (gvmd lists some settings only once written; set setting_id)" unless id

    # gvmd decodes <value> as base64. A plain value is rejected outright
    # ("Value cannot be decoded to valid UTF-8", measured against gvmd 26.42
    # on 2026-10-20) -- get_settings, by contrast, returns it plain.
    # pack('m0') is strict base64 without the base64 gem, as in gvm_scan_config.
    xml = "<modify_setting setting_id=\"#{id}\">" \
          "<value>#{[desired_value(context, name, should)].pack('m0')}</value>" \
          '</modify_setting>'
    transport_command(context, xml)
  end

  def delete(_context, name)
    raise Puppet::ResourceError, "GVM user settings cannot be deleted (setting: #{name}). " \
                                 'Use ensure => present with a reset value instead.'
  end

  # Fetch the name => UUID map directly from GMP. Used by setting_id when the
  # cache populated by #get is unavailable (e.g. set called without a prior get).
  def fetch_setting_ids(context)
    response = transport_command(context, '<get_settings/>')
    return {} unless response

    load_rexml_xpath
    setting_ids_in(response)
  end

  private

  # Setting name => UUID, skipping any id that is not a UUID.
  def setting_ids_in(response)
    REXML::XPath.match(response, '//setting').each_with_object({}) do |element, ids|
      name = REXML::XPath.first(element, 'name')&.text
      id   = element.attributes['id']
      ids[name] = id if name && id&.match?(UUID_PATTERN)
    end
  end

  def desired_value(context, setting_name, should)
    value, filter = should.values_at(:value, :filter_name)
    unless [value, filter].compact.size == 1
      raise Puppet::ResourceError, "gvm_user_setting '#{setting_name}': set exactly one of value and filter_name"
    end
    return value.to_s unless filter

    id = resolve_name_to_id(context, 'filter', filter)
    raise Puppet::ResourceError, "gvm_user_setting '#{setting_name}': GVM filter not found: #{filter}" unless id

    id
  end

  # Filter UUID => name for every filter the transport user can see.
  def fetch_filter_names(context)
    response = transport_command(context, '<get_filters filter="rows=-1"/>')
    return {} unless response

    REXML::XPath.match(response, '/get_filters_response/filter').to_h do |element|
      [element.attributes['id'], REXML::XPath.first(element, 'name')&.text]
    end
  end

  # Resolve a setting name to its UUID. Prefers the cache populated by #get,
  # but falls back to a fresh GMP lookup so #update does not depend on #get
  # having run first in the same provider instance.
  def setting_id(context, setting_name)
    @setting_ids = fetch_setting_ids(context) unless @setting_ids&.key?(setting_name)
    @setting_ids[setting_name]
  end
end
