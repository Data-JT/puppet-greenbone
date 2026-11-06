# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmFilter; end

# Provider for gvm_filter resources via the GMP Unix socket.
class Puppet::Provider::GvmFilter::GvmFilter < Puppet::Provider::GvmBaseProvider
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:term]    = canonical_term(resource[:term]) if resource.key?(:term)
      resource[:comment] = presence(resource[:comment])    if resource.key?(:comment)
    end
  end

  def get(context)
    # rows=-1: GMP pages list responses and defaults to TEN rows; without it
    # every filter after the tenth reads as absent and Puppet tries to create
    # one that exists ("Filter exists already").
    response = transport_command(context, '<get_filters filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    # Direct children only: the response also carries <filters> describing the
    # query itself, whose <term> must not be mistaken for a filter's.
    REXML::XPath.match(response, '/get_filters_response/filter').map do |el|
      {
        ensure:      'present',
        name:        REXML::XPath.first(el, 'name')&.text,
        filter_type: REXML::XPath.first(el, 'type')&.text,
        term:        REXML::XPath.first(el, 'term')&.text.to_s,
        comment:     presence(REXML::XPath.first(el, 'comment')&.text),
      }
    end
  end

  def create(context, name, should)
    context.notice("Creating GVM filter '#{name}'")
    transport_command(context, "<create_filter><name>#{xe(name)}</name>#{body(should)}</create_filter>")
  end

  def update(context, name, should)
    context.notice("Updating GVM filter '#{name}'")
    id = resolve_name_to_id(context, 'filter', name)
    raise Puppet::ResourceError, "GVM filter not found for update: #{name}" unless id

    transport_command(context, "<modify_filter filter_id=\"#{id}\">#{body(should)}</modify_filter>")
  end

  def delete(context, name)
    context.notice("Deleting GVM filter '#{name}'")
    id = resolve_name_to_id(context, 'filter', name)
    raise Puppet::ResourceError, "GVM filter not found for delete: #{name}" unless id

    # gvmd deletes a filter even while a user setting points at it (measured
    # 2026-10-20) and leaves the setting dangling, so ensure=absent on a
    # filter in use should go together with repointing that setting.
    transport_command(context, "<delete_filter filter_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  # Comment is always sent, as an empty element when unset, so removing it
  # from the manifest clears it instead of leaving the old text behind.
  def body(should)
    "<comment>#{xe(should[:comment])}</comment>" \
      "<term>#{xe(should[:term])}</term>" \
      "<type>#{xe(should[:filter_type] || 'result')}</type>"
  end

  # The term as gvmd will store it. See the type docs for the measurements.
  def canonical_term(term)
    words = term.to_s.split
    if words.any? { |word| word.start_with?('rows=-1') }
      raise Puppet::ResourceError,
            "gvm_filter term '#{term}': rows=-1 is stored as the user's Max Rows Per Page value, " \
            'which would never match. Write the row count instead.'
    end

    words << 'first=1'   unless keyword?(words, 'first')
    words << 'rows=10'   unless keyword?(words, 'rows')
    words << 'sort=name' unless keyword?(words, 'sort') || keyword?(words, 'sort-reverse')
    words.join(' ')
  end

  def keyword?(words, key)
    words.any? { |word| word.start_with?("#{key}=") }
  end
end
