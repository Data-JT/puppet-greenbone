# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmOverride; end

# Provider for gvm_override resources via the GMP Unix socket.
class Puppet::Provider::GvmOverride::GvmOverride < Puppet::Provider::GvmBaseProvider
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:text]  = normalize_text(resource[:text])   if resource.key?(:text)
      resource[:hosts] = normalize_hosts(resource[:hosts]) if resource.key?(:hosts)
      # The schema default for new_severity, kept here because puppet-strings
      # cannot document a negative default (see the type). The Resource API
      # canonicalizes a declared resource before Puppet applies defaults, so
      # this makes the property managed exactly as `default: -1` did. get()
      # always sets the key, so a value read from gvmd is never replaced.
      resource[:new_severity] = -1 unless resource.key?(:new_severity)
    end
  end

  def get(context)
    # TWO load-bearing attributes on this one call.
    #
    # rows=-1: GMP pages list responses and defaults to TEN rows. Without it
    # this provider sees only the first ten overrides and reports every one
    # after that as absent, so Puppet tries to CREATE an override that already
    # exists. Same failure the schedule provider hit on 2026-08-20.
    #
    # details=1: WITHOUT it gvmd omits <hosts> and <port> from the response
    # entirely -- the other fields all come back, so the omission is silent.
    # Both would then read as nil on every run while the manifest sets them,
    # and Puppet would "update" the override forever without ever converging.
    # Measured against gvmd 26.37 on 2026-09-07: details=0 returned text,
    # severity and new_severity but no hosts and no port; details=1 returned
    # all four.
    response = transport_command(context, '<get_overrides filter="rows=-1" details="1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//override').map { |element| parse_override(element) }.compact
  end

  def create(context, name, should)
    context.notice("Creating GVM override '#{name}'")
    transport_command(context, "<create_override>#{body(name, should)}</create_override>")
  end

  def update(context, name, should)
    context.notice("Updating GVM override '#{name}'")
    id = resolve_override_id(context, name)
    raise Puppet::ResourceError, "GVM override not found for update: #{name}" unless id

    # Every field is resent, never a partial. modify_override rejects a call
    # without <new_severity> outright ("new_severity is required", measured
    # 2026-09-07), and GMP modify_* semantics do not guarantee that an omitted
    # child is left alone rather than cleared. Sending the full desired state
    # is correct under either behaviour.
    transport_command(context, "<modify_override override_id=\"#{id}\">#{body(name, should)}</modify_override>")
  end

  def delete(context, name)
    context.notice("Deleting GVM override '#{name}'")
    id = resolve_override_id(context, name)
    raise Puppet::ResourceError, "GVM override not found for delete: #{name}" unless id

    transport_command(context, "<delete_override override_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  def parse_override(element)
    name, text = split_marker(REXML::XPath.first(element, 'text')&.text.to_s)
    # No marker means the override was not created by this type. Skipping it
    # here is what keeps hand-made overrides in the web UI safe from Puppet.
    return nil unless name

    {
      ensure:       'present',
      name:         name,
      text:         text,
      nvt_oid:      REXML::XPath.first(element, 'nvt')&.attributes&.[]('oid'),
      hosts:        normalize_hosts(presence(REXML::XPath.first(element, 'hosts')&.text)),
      port:         presence(REXML::XPath.first(element, 'port')&.text),
      severity:     to_num(REXML::XPath.first(element, 'severity')&.text),
      new_severity: to_num(REXML::XPath.first(element, 'new_severity')&.text),
      # gvmd answers 1/0 here even though create/modify take -1/0. Comparing
      # against the sent value instead of the returned one would rewrite the
      # override on every single run.
      active:       REXML::XPath.first(element, 'active')&.text.to_s.strip == '1',
    }
  end

  # <threat> and <new_threat> are absent on purpose: gvmd DERIVES both from
  # severity and new_severity ("False Positive" for -1) and ignores them on
  # write, so managing them would be a permanent diff against a value this
  # provider cannot set.
  def body(title, should)
    parts = ["<text>#{xe(marked_text(title, should[:text]))}</text>", "<nvt oid=\"#{should[:nvt_oid]}\"/>"]
    parts.concat(scope_elements(should))
    parts << "<new_severity>#{fmt_num(should[:new_severity])}</new_severity>"
    # -1 is GMP for "active with no expiry"; 0 is inactive. A positive value
    # would mean "active for N days", which this type deliberately does not
    # expose -- see the type docs.
    parts << "<active>#{(should[:active] == false) ? '0' : '-1'}</active>"
    parts.join
  end

  # hosts, port and severity narrow the override; each is left out when unset.
  def scope_elements(should)
    hosts    = presence(should[:hosts])
    port     = presence(should[:port])
    severity = should[:severity]
    elements = []
    elements << "<hosts>#{xe(hosts)}</hosts>" if hosts
    elements << "<port>#{xe(port)}</port>" if port
    elements << "<severity>#{fmt_num(severity)}</severity>" if severity
    elements
  end

  # The override is found by the [puppet:<title>] marker in its text.
  def resolve_override_id(context, title)
    response = transport_command(context, '<get_overrides filter="rows=-1"/>')
    return nil unless response

    load_rexml_xpath
    element = REXML::XPath.match(response, '//override').find do |candidate|
      split_marker(REXML::XPath.first(candidate, 'text')&.text.to_s).first == title
    end
    element && uuid_of(element, "override '#{title}'")
  end

  def marked_text(title, text)
    "#{normalize_text(text)}\n\n[puppet:#{title}]"
  end

  # Recovers the Puppet resource title from the override text. See the type
  # docs for why an override needs one at all: GMP gives it no name.
  #
  # Deliberately a method rather than a constant. Puppet loads a pluginsynced
  # provider file twice in a single agent process, and a constant here printed
  # "warning: already initialized constant ... MARKER" on stderr for every run
  # on the node -- harmless, but it is the kind of noise that trains you to
  # ignore warnings from this provider.
  def marker
    @marker ||= %r{\A(.*?)\s*\[puppet:([^\]\n]+)\]\s*\z}m
  end

  # Returns [name, text_without_marker], or [nil, raw] when unmarked.
  def split_marker(raw)
    text = raw.to_s
    match = marker.match(text)
    return [nil, text] unless match

    [match[2], normalize_text(match[1])]
  end

  def normalize_text(str)
    str.to_s.gsub("\r\n", "\n").strip
  end

  # gvmd stores the host list verbatim, so "a, b" and "a,b" are two different
  # stored values for the same intent and whichever one the manifest did not
  # use would churn every run.
  def normalize_hosts(str)
    cleaned = str.to_s.split(',').map(&:strip).reject(&:empty?).join(',')
    cleaned.empty? ? nil : cleaned
  end

  # Compare as Integer where the value is integral, so a manifest's -1 and
  # gvmd's "-1" are the same object to the Resource API's equality check.
  # nil for an empty or unparsable value.
  def to_num(str)
    number = Float(presence(str).to_s, exception: false)
    number && integral(number)
  end

  def fmt_num(num)
    integral(num.to_f).to_s
  end

  def integral(number)
    whole = number.truncate
    (number == whole) ? whole : number
  end
end
