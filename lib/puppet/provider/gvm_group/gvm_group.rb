# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmGroup; end

# Provider for gvm_group resources via the GMP Unix socket.
class Puppet::Provider::GvmGroup::GvmGroup < Puppet::Provider::GvmBaseProvider
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:users]   = normalize_users(resource[:users]) if resource.key?(:users)
      resource[:comment] = presence(resource[:comment])      if resource.key?(:comment)
    end
  end

  def get(context)
    # rows=-1: GMP defaults to ten rows per list; see gvm_filter.
    response = transport_command(context, '<get_groups filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '/get_groups_response/group').map do |el|
      {
        ensure:  'present',
        name:    REXML::XPath.first(el, 'name')&.text,
        users:   normalize_users(REXML::XPath.first(el, 'users')&.text.to_s.split(',')),
        comment: presence(REXML::XPath.first(el, 'comment')&.text),
      }
    end
  end

  def create(context, name, should)
    context.notice("Creating GVM group '#{name}'")
    transport_command(context, "<create_group><name>#{xe(name)}</name>#{body(should)}</create_group>")
  end

  def update(context, name, should)
    context.notice("Updating GVM group '#{name}'")
    id = resolve_name_to_id(context, 'group', name)
    raise Puppet::ResourceError, "GVM group not found for update: #{name}" unless id

    transport_command(context, "<modify_group group_id=\"#{id}\"><name>#{xe(name)}</name>#{body(should)}</modify_group>")
  end

  def delete(context, name)
    context.notice("Deleting GVM group '#{name}'")
    id = resolve_name_to_id(context, 'group', name)
    raise Puppet::ResourceError, "GVM group not found for delete: #{name}" unless id

    # A Super permission naming this group as its resource goes with it; that
    # is the intended effect of removing the group.
    transport_command(context, "<delete_group group_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  # <users> is always sent, empty when there are none, so emptying the list in
  # the manifest empties the group (verified: modify_group with <users></users>
  # leaves it with no members).
  def body(should)
    "<comment>#{xe(should[:comment])}</comment>" \
      "<users>#{xe(normalize_users(should[:users]).join(','))}</users>"
  end

  def normalize_users(list)
    Array(list).map { |user| user.to_s.strip }.reject(&:empty?).uniq.sort
  end
end
