# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmUser; end

# Provider for gvm_user resources via the GMP Unix socket.
class Puppet::Provider::GvmUser::GvmUser < Puppet::Provider::GvmBaseProvider
  def get(context)
    # rows=-1 is load-bearing. GMP pages list responses and defaults to TEN
    # rows, so without it this provider sees only the first ten users and
    # reports every one after that as absent. Puppet then tries to CREATE an
    # object that exists ("GMP error 400: ... exists already") and, for an
    # entry set to ensure=absent, does nothing at all while reporting success.
    # Both were observed on a production gvmd on 2026-08-20, at exactly the point
    # the instance grew past ten users.
    response = transport_command(context, '<get_users filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//user').map do |element|
      role_name = REXML::XPath.first(element, 'role/name')&.text
      {
        ensure:      'present',
        name:        REXML::XPath.first(element, 'name')&.text,
        role_name:   role_name || 'User',
        hosts:       REXML::XPath.first(element, 'hosts')&.text,
        hosts_allow: REXML::XPath.first(element, 'hosts/@allow')&.value == '1',
        source:      REXML::XPath.first(element, 'sources/source')&.text || 'file',
      }
    end
  end

  def create(context, name, should)
    context.notice("Creating GVM user '#{name}'")
    role_id = resolve_role(context, should)
    password = password_for(name, should)

    xml = '<create_user>' \
          "<name>#{xe(name)}</name>" \
          "<password>#{xe(password)}</password>" \
          "<role id=\"#{role_id}\"/>" \
          "#{hosts_xml(should)}" \
          "#{sources_xml(should)}" \
          '</create_user>'
    transport_command(context, xml)
  end

  def update(context, name, should)
    context.notice("Updating GVM user '#{name}'")
    id = resolve_name_to_id(context, 'user', name)
    raise Puppet::ResourceError, "GVM user not found for update: #{name}" unless id

    role_id = resolve_role(context, should)
    password = password_for(name, should)

    xml = "<modify_user user_id=\"#{id}\">" \
          "<name>#{xe(name)}</name>" \
          "#{password ? "<password>#{xe(password)}</password>" : ''}" \
          "<role id=\"#{role_id}\"/>" \
          "#{hosts_xml(should)}" \
          "#{sources_xml(should)}" \
          '</modify_user>'
    transport_command(context, xml)
  end

  def delete(context, name)
    context.notice("Deleting GVM user '#{name}'")
    id = resolve_name_to_id(context, 'user', name)
    raise Puppet::ResourceError, "GVM user not found for delete: #{name}" unless id

    transport_command(context, "<delete_user user_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  def resolve_role(context, should)
    role = should[:role_name]
    id = resolve_name_to_id(context, 'role', role)
    raise Puppet::ResourceError, "GVM role not found: #{role}" unless id

    id
  end

  # A password on an LDAP/RADIUS user is refused, not ignored. create_user
  # replaces it with a random UUID anyway, but modify_user stores it as a
  # working local hash -- and gvmd falls back to that hash for this user
  # whenever LDAP is switched off, so a manifest password would quietly
  # become a second way in (gvmd 26.42 manage_sql_users.c create_user /
  # modify_user).
  def password_for(name, should)
    password = unwrap(should[:password])
    source = should[:source].to_s
    if !password.to_s.empty? && !source.empty? && source != 'file'
      raise Puppet::ResourceError,
            "gvm_user '#{name}': a password is only valid with source => 'file', not '#{source}'"
    end
    password
  end

  def hosts_xml(should)
    hosts = should[:hosts].to_s
    allow = should[:hosts_allow] ? '1' : '0'
    "<hosts allow=\"#{allow}\">#{xe(hosts)}</hosts>"
  end

  # gvmd uses "file" for local password auth; LDAP/RADIUS users carry an explicit
  # source. We always send <sources> so switching a user back to local works too.
  def sources_xml(should)
    source = should[:source].to_s
    source = 'file' if source.empty?
    "<sources><source>#{xe(source)}</source></sources>"
  end
end
