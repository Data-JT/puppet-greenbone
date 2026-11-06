# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require 'yaml'

# Base provider with shared GMP helpers used by all gvm_* providers.
class Puppet::Provider::GvmBaseProvider < Puppet::ResourceApi::SimpleProvider
  UUID_PATTERN = %r{\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z}i

  def self.config_path
    File.join(Puppet.settings[:confdir], 'gvm_transport.yaml')
  end

  def self.build_transport(context)
    require 'puppet/transport/greenbone'
    raw = YAML.safe_load_file(config_path)
    unless raw.is_a?(Hash)
      raise Puppet::ResourceError, "Greenbone transport config at #{config_path} must be a YAML mapping"
    end
    config = raw.transform_keys(&:to_sym)
    [:user, :password, :socket].each do |key|
      value = config[key]
      unless value.is_a?(String) && !value.empty?
        raise Puppet::ResourceError, "Greenbone transport config key '#{key}' must be a non-empty string"
      end
    end
    Puppet::Transport::Greenbone.new(context, config)
  rescue Errno::ENOENT
    raise Puppet::ResourceError,
          "Greenbone transport config not found at #{config_path}; " \
          'ensure the greenbone class is applied before managing gvm_* resources'
  end

  def gvm_transport(context)
    signature = transport_config_signature
    unless @gvm_transport && signature == @transport_config_signature
      @gvm_transport = self.class.build_transport(context)
      @transport_config_signature = signature
    end
    @gvm_transport
  end

  # Wraps transport calls during discovery: missing config returns empty list
  # rather than failing catalog compilation.
  def transport_command(context, xml)
    gvm_transport(context).command(context, xml)
  rescue Puppet::ResourceError => error
    raise unless error.message.start_with?('Greenbone transport config not found at ')

    @transport_config_missing = true
    nil
  end

  def set(context, changes)
    changes = refresh_changes(context, changes) if @transport_config_missing
    super
  end

  # Clearing optional properties: `delete_properties` names optional
  # attributes to clear on update. GMP has no delete parameter; each provider
  # clears a listed attribute by sending its element empty, which is how it
  # already writes an unset value. Types opt in with the custom_insync feature
  # and an Enum of the attributes their provider can clear.
  #
  # Every other attribute returns nil, which hands the comparison back to the
  # Resource API's default.
  def insync?(_context, _name, attribute_name, is_hash, should_hash)
    delete_properties_insync?(is_hash, should_hash) if attribute_name == :delete_properties
  end

  # get() never reports delete_properties, so it is in sync once every listed
  # attribute reads back unset: the clearing update is sent only while one is
  # still set, and the resource converges. Declaring a value for an attribute
  # that is also listed could never converge, so it fails instead.
  def delete_properties_insync?(current, desired)
    requested = deleted_properties(desired)
    conflicting = requested.reject { |attribute| desired[attribute].nil? }
    unless conflicting.empty?
      raise Puppet::ResourceError,
            "Cannot set and delete the same properties: #{conflicting.join(', ')}"
    end

    requested.all? { |attribute| current[attribute].nil? }
  end

  # Whether `should` asks to clear the attribute.
  def deleting?(should, attribute)
    deleted_properties(should).include?(attribute)
  end

  # Look up a named object's UUID from GMP using get_<type>s with a filter.
  # Returns nil if not found; raises if the server returns a malformed UUID.
  def resolve_name_to_id(context, type, name)
    response = transport_command(context, "<get_#{type}s filter=\"name=#{gmp_escape_filter(name)}\"/>")
    return nil unless response

    load_rexml_xpath
    element = REXML::XPath.match(response, "//#{type}").find do |candidate|
      REXML::XPath.first(candidate, 'name')&.text == name
    end
    element && uuid_of(element, "#{type} '#{name}'")
  end

  # XML-escape text for safe inclusion in element content. Shared by all
  # gvm_* providers so the escaping rules cannot drift between them.
  def xe(str)
    str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  private

  # The element's id attribute, refused unless it is a UUID: every caller
  # interpolates it into the next GMP command.
  def uuid_of(element, what)
    checked_uuid(element.attributes['id'], what)
  end

  def checked_uuid(id, what)
    raise Puppet::ResourceError, "GMP returned invalid UUID for #{what}: #{id.inspect}" unless id&.match?(UUID_PATTERN)

    id
  end

  # The plain value of a possibly Sensitive one. The Resource API hands a
  # sensitive attribute to the provider wrapped.
  def unwrap(value)
    value.respond_to?(:unwrap) ? value.unwrap : value
  end

  # The stripped string, or nil when it is empty: how every provider reads an
  # optional GMP text element, which gvmd sends empty rather than omitting.
  def presence(str)
    stripped = str.to_s.strip
    stripped.empty? ? nil : stripped
  end

  def load_rexml_xpath
    require 'rexml/xpath'
  end

  def transport_config_signature
    stat = File.stat(self.class.config_path)
    [stat.mtime.to_f, stat.size]
  rescue Errno::ENOENT
    nil
  end

  def refresh_changes(context, changes)
    @gvm_transport = nil
    @transport_config_signature = nil
    @transport_config_missing = false
    current = get(context) || []

    changes.transform_values do |change|
      should = change[:should]
      change.merge(is: current_state(context, current, should) || absent_state(context, should))
    end
  end

  def current_state(context, current, should)
    namevars = context.type.namevars
    current.find { |resource| namevars.all? { |namevar| resource[namevar] == should[namevar] } }
  end

  def absent_state(context, should)
    context.type.namevars.to_h { |namevar| [namevar, should[namevar]] }.merge(ensure: 'absent')
  end

  def deleted_properties(should)
    Array(should[:delete_properties]).map(&:to_sym)
  end

  def gmp_escape_filter(str)
    # GMP filter strings use double-quotes for phrase matching.
    # Strip embedded double-quotes rather than replacing them with &quot;:
    # an XML attribute decoder turns &quot; back into " before GMP parses the
    # filter, which would close the phrase boundary and corrupt the filter.
    # Exact name matching is always done in Ruby after receiving the response,
    # so a slightly broader filter is safe.
    "&quot;#{str.to_s.delete('"')}&quot;"
  end
end
