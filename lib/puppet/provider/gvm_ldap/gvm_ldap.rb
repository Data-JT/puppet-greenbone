# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmLdap; end

# Provider for gvm_ldap: manages the ldap_connect auth group via GMP.
#
# auth_conf_setting carries <key> and <value> as CHILD ELEMENTS, in both
# directions. An earlier version of this provider wrote them as attributes;
# gvmd skips a setting without a key or value child and still answers
# modify_auth with 200 OK, so every run "enabled" LDAP and changed nothing,
# while get() read back nothing and reported absent forever. Verified against
# gvmd 26.42 source (gmp.c CLIENT_MODIFY_AUTH / describe_auth) and live on
# 2026-10-20.
class Puppet::Provider::GvmLdap::GvmLdap < Puppet::Provider::GvmBaseProvider
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:cacert] = normalize_pem(resource[:cacert]) if resource.key?(:cacert)
    end
  end

  def get(context)
    response = transport_command(context, '<describe_auth/>')
    return [] unless response

    load_rexml_xpath
    group = REXML::XPath.first(response, "//group[@name='#{group_name}']")
    return [] unless group

    settings = read_settings(group)
    [{
      ensure:          (settings['enable'] == 'true') ? 'present' : 'absent',
      name:            'ldap_connect',
      ldaphost:        presence(settings['ldaphost']),
      authdn:          presence(settings['authdn']),
      cacert:          normalize_pem(settings['cacert']),
      # describe_auth prints allow-plaintext with %i (0/1) but ldaps-only and
      # enable as true/false. Accept either spelling for both.
      allow_plaintext: truthy?(settings['allow-plaintext']),
      ldaps_only:      truthy?(settings['ldaps-only']),
    }]
  end

  def create(context, name, should)
    context.notice("Enabling GVM LDAP authentication '#{name}'")
    enable_ldap(context, should)
  end

  def update(context, name, should)
    context.notice("Updating GVM LDAP authentication '#{name}'")
    enable_ldap(context, should)
  end

  # Only switches LDAP off; the stored host and DN stay.
  def delete(context, name)
    context.notice("Disabling GVM LDAP authentication '#{name}'")
    send_settings(context, [auth_setting('enable', 'false')])
  end

  private

  # Deliberately a method, not a constant: Puppet loads a pluginsynced provider
  # twice per agent process and a constant warns "already initialized" on
  # every run (same fix as gvm_override's marker).
  def group_name
    'method:ldap_connect'
  end

  # { key => value } of the group's auth_conf_setting children.
  def read_settings(group)
    settings = {}
    REXML::XPath.each(group, 'auth_conf_setting') do |setting|
      key = REXML::XPath.first(setting, 'key')&.text
      settings[key] = REXML::XPath.first(setting, 'value')&.text.to_s if key
    end
    settings
  end

  def enable_ldap(context, should)
    ldaphost = should[:ldaphost]
    authdn = should[:authdn]
    raise Puppet::ResourceError, 'gvm_ldap requires ldaphost when ensure => present' unless ldaphost
    raise Puppet::ResourceError, 'gvm_ldap requires authdn when ensure => present' unless authdn

    # The cacert goes first and on its own. manage_set_ldap_info writes enable,
    # host and DN before it validates the certificate, so in one call a bad
    # cacert fails the request AFTER LDAP was already switched on with the
    # new host -- half applied. Alone, a bad certificate changes nothing.
    cacert = unwrap(should[:cacert])
    send_settings(context, [auth_setting('cacert', cacert)]) if cacert

    send_settings(context, [
                    auth_setting('enable', 'true'),
                    auth_setting('ldaphost', ldaphost),
                    auth_setting('authdn', authdn),
                    auth_setting('allow-plaintext', should[:allow_plaintext] ? 'true' : 'false'),
                    auth_setting('ldaps-only', should[:ldaps_only] ? 'true' : 'false'),
                  ])
  end

  def send_settings(context, settings)
    transport_command(context, "<modify_auth><group name=\"#{group_name}\">#{settings.join}</group></modify_auth>")
  end

  def auth_setting(key, value)
    "<auth_conf_setting><key>#{key}</key><value>#{xe(value)}</value></auth_conf_setting>"
  end

  def truthy?(value)
    ['1', 'true'].include?(value.to_s.strip)
  end

  def normalize_pem(str)
    presence(str.to_s.gsub("\r\n", "\n"))
  end
end
