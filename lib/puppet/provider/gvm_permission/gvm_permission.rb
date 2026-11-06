# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmPermission; end

# Provider for gvm_permission resources via the GMP Unix socket.
#
# GMP shape, measured against gvmd 26.42 on 2026-10-20: create/modify take
# <name>, <comment>, <subject id=""><type/></subject> and an optional
# <resource id=""><type/></resource>; get_permissions returns the subject and
# resource with their <name> and <type>, so names round-trip without a second
# lookup.
class Puppet::Provider::GvmPermission::GvmPermission < Puppet::Provider::GvmBaseProvider
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:permission]    = canonical_permission(resource[:permission]) if resource.key?(:permission)
      resource[:comment]       = normalize_text(resource[:comment])          if resource.key?(:comment)
      resource[:resource_type] = presence(resource[:resource_type])          if resource.key?(:resource_type)
      resource[:resource_name] = presence(resource[:resource_name])          if resource.key?(:resource_name)
    end
  end

  def get(context)
    # rows=-1: GMP defaults to ten rows per list, and there are ~270 built-in
    # permissions ahead of any managed one.
    response = transport_command(context, '<get_permissions filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '/get_permissions_response/permission').map { |element| parse(element) }.compact
  end

  def create(context, name, should)
    context.notice("Creating GVM permission '#{name}'")
    transport_command(context, "<create_permission>#{body(context, name, should)}</create_permission>")
  end

  def update(context, name, should)
    context.notice("Updating GVM permission '#{name}'")
    id = resolve_permission_id(context, name)
    raise Puppet::ResourceError, "GVM permission not found for update: #{name}" unless id

    transport_command(context, "<modify_permission permission_id=\"#{id}\">#{body(context, name, should)}</modify_permission>")
  end

  def delete(context, name)
    context.notice("Deleting GVM permission '#{name}'")
    id = resolve_permission_id(context, name)
    raise Puppet::ResourceError, "GVM permission not found for delete: #{name}" unless id

    transport_command(context, "<delete_permission permission_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  def parse(element)
    title, comment = split_marker(REXML::XPath.first(element, 'comment')&.text.to_s)
    # Unmarked means not ours: the built-in permissions, and anything made by
    # hand in the web UI.
    return nil unless title

    {
      ensure:       'present',
      name:         title,
      permission:   canonical_permission(REXML::XPath.first(element, 'name')&.text),
      subject_type: REXML::XPath.first(element, 'subject/type')&.text,
      subject_name: REXML::XPath.first(element, 'subject/name')&.text,
      comment:      comment,
    }.merge(parse_resource(element))
  end

  # gvmd answers an unrestricted permission with an empty <resource id="">.
  def parse_resource(element)
    return { resource_type: nil, resource_name: nil } if REXML::XPath.first(element, 'resource')&.attributes&.[]('id').to_s.empty?

    {
      resource_type: presence(REXML::XPath.first(element, 'resource/type')&.text),
      resource_name: presence(REXML::XPath.first(element, 'resource/name')&.text),
    }
  end

  def body(context, title, should)
    subject_type = should[:subject_type]
    subject_id = resolve_named(context, title, subject_type, should[:subject_name])
    resource = resource_pair(title, should)
    parts = ["<name>#{xe(should[:permission])}</name>",
             "<comment>#{xe(marked_comment(title, should[:comment]))}</comment>",
             "<subject id=\"#{subject_id}\"><type>#{xe(subject_type)}</type></subject>"]
    if resource
      type, name = resource
      parts << "<resource id=\"#{resolve_named(context, title, type, name)}\"><type>#{xe(type)}</type></resource>"
    end
    parts.join
  end

  # [resource_type, resource_name], or nil when the permission is not limited
  # to one resource. Half a resource is refused.
  def resource_pair(title, should)
    pair = [presence(should[:resource_type]), presence(should[:resource_name])]
    return nil if pair.none?
    raise Puppet::ResourceError, "gvm_permission '#{title}': set resource_type and resource_name together" unless pair.all?

    pair
  end

  def resolve_named(context, title, type, object_name)
    id = resolve_name_to_id(context, type, object_name)
    raise Puppet::ResourceError, "gvm_permission '#{title}': GVM #{type} not found: #{object_name}" unless id

    id
  end

  # The permission is found by the [puppet:<title>] marker in its comment.
  def resolve_permission_id(context, title)
    response = transport_command(context, '<get_permissions filter="rows=-1"/>')
    return nil unless response

    load_rexml_xpath
    element = REXML::XPath.match(response, '/get_permissions_response/permission').find do |candidate|
      split_marker(REXML::XPath.first(candidate, 'comment')&.text.to_s).first == title
    end
    element && uuid_of(element, "permission '#{title}'")
  end

  # gvmd stores command names lower-cased and Super as "Super"
  # (manage_sql_permissions.c check_permission_args).
  def canonical_permission(str)
    permission = str.to_s.strip
    permission.casecmp?('super') ? 'Super' : permission.downcase
  end

  def marked_comment(title, comment)
    text = normalize_text(comment)
    text ? "#{text}\n\n[puppet:#{title}]" : "[puppet:#{title}]"
  end

  # Method rather than constant; see gvm_override for the double-load warning.
  def marker
    @marker ||= %r{\A(.*?)\s*\[puppet:([^\]\n]+)\]\s*\z}m
  end

  # Returns [name, comment_without_marker], or [nil, raw] when unmarked.
  def split_marker(raw)
    text = raw.to_s
    match = marker.match(text)
    return [nil, text] unless match

    [match[2], normalize_text(match[1])]
  end

  def normalize_text(str)
    presence(str.to_s.gsub("\r\n", "\n"))
  end
end
