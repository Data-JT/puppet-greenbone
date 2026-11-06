# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmTarget; end

# Provider for gvm_target resources via the GMP Unix socket.
class Puppet::Provider::GvmTarget::GvmTarget < Puppet::Provider::GvmBaseProvider
  # gvmd rewrites hosts and exclude_hosts on write (clean_hosts in
  # manage_utils.c): newlines become commas, each entry is trimmed, empties
  # and duplicates are dropped, and the rest is joined with ", ". A literal
  # comparison saw "a,b" in hiera against "a, b" in gvmd as a change on every
  # run, and the update it triggered failed with "Target is in use".
  def canonicalize(_context, resources)
    resources.each do |resource|
      resource[:hosts]         = clean_hosts(resource[:hosts])         if resource.key?(:hosts)
      resource[:exclude_hosts] = clean_hosts(resource[:exclude_hosts]) if resource.key?(:exclude_hosts)
    end
  end

  def get(context)
    # rows=-1 is load-bearing. GMP pages list responses and defaults to TEN
    # rows, so without it this provider sees only the first ten targets and
    # reports every one after that as absent. Puppet then tries to CREATE an
    # object that exists ("GMP error 400: ... exists already") and, for an
    # entry set to ensure=absent, does nothing at all while reporting success.
    # Both were observed on a production gvmd on 2026-08-20, at exactly the point
    # the instance grew past ten targets.
    response = transport_command(context, '<get_targets filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//target').map { |element| parse_target(element) }
  end

  def create(context, name, should)
    context.notice("Creating GVM target '#{name}'")
    transport_command(context, build_create_xml(name, should, resolve_port_list(context, should[:port_list_name])))
  end

  # Sends only the elements that differ from what gvmd holds now. gvmd
  # refuses hosts, exclude_hosts, port_list, the three flags and the
  # credentials on a target any task references -- as soon as the element is
  # PRESENT in modify_target, whether or not its value changes (modify_target
  # in manage_sql_targets.c) -- while comment and alive_tests may change at
  # any time. Sending every attribute therefore made a comment edit fail with
  # "Target is in use"; now only a real change to a locked attribute does,
  # and that one gvmd will not allow short of deleting the tasks.
  def update(context, name, should)
    context.notice("Updating GVM target '#{name}'")
    id, is = current_target(context, name)
    raise Puppet::ResourceError, "GVM target not found for update: #{name}" unless id

    port_list = should[:port_list_name]
    port_list_id = (port_list == is[:port_list_name]) ? nil : resolve_port_list(context, port_list)
    xml = build_modify_xml(id, should, is, port_list_id)
    return context.debug("GVM target '#{name}' already matches; nothing to send") unless xml

    transport_command(context, xml)
  end

  def delete(context, name)
    context.notice("Deleting GVM target '#{name}'")
    id = resolve_name_to_id(context, 'target', name)
    raise Puppet::ResourceError, "GVM target not found for delete: #{name}" unless id

    transport_command(context, "<delete_target target_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  # Method rather than constant; see gvm_override for the double-load warning.
  def flags
    [:allow_simultaneous_ips, :reverse_lookup_only, :reverse_lookup_unify]
  end

  def resolve_port_list(context, port_list)
    id = resolve_name_to_id(context, 'port_list', port_list)
    raise Puppet::ResourceError, "GVM port list not found: #{port_list}" unless id

    id
  end

  def build_create_xml(name, should, port_list_id)
    parts = ["<name>#{xe(name)}</name>", "<hosts>#{xe(should[:hosts])}</hosts>", "<port_list id=\"#{port_list_id}\"/>"]
    { comment: 'comment', exclude_hosts: 'exclude_hosts', alive_test: 'alive_tests' }.each do |attribute, element|
      value = should[attribute]
      parts << "<#{element}>#{xe(value)}</#{element}>" if value
    end
    flags.each { |flag| parts << "<#{flag}>#{flag_value(should[flag])}</#{flag}>" }
    "<create_target>#{parts.join}</create_target>"
  end

  # Returns nil when nothing differs. port_list_id is set only when the port
  # list changes.
  def build_modify_xml(id, should, is, port_list_id)
    parts = []
    parts << "<comment>#{xe(should[:comment])}</comment>" if comment_changed?(should, is)
    parts.concat(host_elements(should, is))
    parts << "<port_list id=\"#{port_list_id}\"/>" if port_list_id
    alive_test = should[:alive_test]
    parts << "<alive_tests>#{xe(alive_test)}</alive_tests>" if alive_test && alive_test != is[:alive_test]
    flags.each do |flag|
      wanted = flag_value(should[flag])
      parts << "<#{flag}>#{wanted}</#{flag}>" if wanted != flag_value(is[flag])
    end
    "<modify_target target_id=\"#{id}\">#{parts.join}</modify_target>" unless parts.empty?
  end

  # delete_properties clears the comment with an empty element; an undeclared
  # comment is left alone.
  def comment_changed?(should, is)
    managed = should.key?(:comment) || deleting?(should, :comment)
    managed && should[:comment].to_s != is[:comment].to_s
  end

  # gvmd rejects <hosts> without <exclude_hosts> (status 13) and rebuilds
  # both together, so a change to either sends the pair. An unset
  # exclude_hosts differs from a stored one and goes out empty, which is also
  # how delete_properties clears it.
  def host_elements(should, is)
    hosts = should[:hosts]
    exclude_hosts = should[:exclude_hosts]
    unchanged = clean_hosts(hosts) == clean_hosts(is[:hosts]) && clean_hosts(exclude_hosts) == clean_hosts(is[:exclude_hosts])
    return [] if unchanged

    ["<hosts>#{xe(hosts)}</hosts>", "<exclude_hosts>#{xe(exclude_hosts)}</exclude_hosts>"]
  end

  def flag_value(value)
    value ? 1 : 0
  end

  # The target's UUID and current state in one GMP call, read at update time
  # rather than taken from the run's earlier get().
  def current_target(context, target_name)
    response = transport_command(context, "<get_targets filter=\"name=#{gmp_escape_filter(target_name)}\"/>")
    return nil unless response

    load_rexml_xpath
    element = REXML::XPath.match(response, '//target').find { |candidate| REXML::XPath.first(candidate, 'name')&.text == target_name }
    element && [uuid_of(element, "target '#{target_name}'"), parse_target(element)]
  end

  def parse_target(element)
    {
      ensure:                 'present',
      name:                   REXML::XPath.first(element, 'name')&.text,
      comment:                REXML::XPath.first(element, 'comment')&.text,
      hosts:                  REXML::XPath.first(element, 'hosts')&.text,
      exclude_hosts:          REXML::XPath.first(element, 'exclude_hosts')&.text,
      port_list_name:         REXML::XPath.first(element, 'port_list/name')&.text,
      alive_test:             REXML::XPath.first(element, 'alive_tests')&.text,
      allow_simultaneous_ips: REXML::XPath.first(element, 'allow_simultaneous_ips')&.text == '1',
      reverse_lookup_only:    REXML::XPath.first(element, 'reverse_lookup_only')&.text == '1',
      reverse_lookup_unify:   REXML::XPath.first(element, 'reverse_lookup_unify')&.text == '1',
    }
  end

  # Mirrors gvmd's clean_hosts. An empty list is nil, the form get() reads
  # back for gvmd's empty <exclude_hosts/>, so '' in hiera is not a change.
  def clean_hosts(str)
    cleaned = str.to_s.tr("\n", ',').split(',').map(&:strip).reject(&:empty?).uniq
    cleaned.empty? ? nil : cleaned.join(', ')
  end
end
