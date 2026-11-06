# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmTask; end

# Provider for gvm_task resources via the GMP Unix socket.
class Puppet::Provider::GvmTask::GvmTask < Puppet::Provider::GvmBaseProvider
  def get(context)
    # rows=-1 is load-bearing. GMP pages list responses and defaults to TEN
    # rows, so without it this provider sees only the first ten tasks and
    # reports every one after that as absent. Puppet then tries to CREATE an
    # object that exists ("GMP error 400: ... exists already") and, for an
    # entry set to ensure=absent, does nothing at all while reporting success.
    # Both were observed on a production gvmd on 2026-08-20, at exactly the point
    # the instance grew past ten tasks.
    response = transport_command(context, '<get_tasks filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//task').map { |element| parse_task(element) }
  end

  def create(context, name, should)
    context.notice("Creating GVM task '#{name}'")
    schedule = should[:schedule_name]
    ids = {
      target:   resolve_required(context, 'target', should[:target_name], 'target'),
      config:   resolve_required(context, 'config', should[:config_name], 'scan config'),
      scanner:  resolve_required(context, 'scanner', should[:scanner_name], 'scanner'),
      schedule: schedule && resolve_name_to_id(context, 'schedule', schedule),
    }
    transport_command(context, build_create_xml(name, should, ids))
  end

  def update(context, name, should)
    context.notice("Updating GVM task '#{name}'")
    id = resolve_name_to_id(context, 'task', name)
    raise Puppet::ResourceError, "GVM task not found for update: #{name}" unless id

    # gvmd forbids changing target/config/scanner once a task has left the
    # 'New' state (GMP 400 "Status must be New to edit scanner"). Only send
    # those elements when they actually differ from the current value, so
    # preference-only updates (max_hosts/max_checks/auto_delete/schedule) still
    # apply to tasks that have already run.
    current = get(context).find { |existing| existing[:name] == name } || {}
    schedule = should[:schedule_name]
    ids = {
      target:   changed_id(context, 'target', should, current),
      config:   changed_id(context, 'config', should, current),
      scanner:  changed_id(context, 'scanner', should, current),
      schedule: schedule && resolve_name_to_id(context, 'schedule', schedule),
    }
    transport_command(context, build_modify_xml(id, should, ids))
  end

  def delete(context, name)
    context.notice("Deleting GVM task '#{name}'")
    id = resolve_name_to_id(context, 'task', name)
    raise Puppet::ResourceError, "GVM task not found for delete: #{name}" unless id

    transport_command(context, "<delete_task task_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  def parse_task(element)
    # auto_delete_data = 0 means "keep all reports" (auto-delete off).
    # auto_delete_data > 0 means "keep N reports" (auto-delete on).
    # When off we still report auto_delete_data as 5 so it matches the type
    # default and does not cause drift if the attribute is left unset.
    keep = preference(element, 'auto_delete_data').to_i
    auto_delete = keep.positive?
    {
      ensure:           'present',
      name:             REXML::XPath.first(element, 'name')&.text,
      comment:          REXML::XPath.first(element, 'comment')&.text,
      target_name:      REXML::XPath.first(element, 'target/name')&.text,
      config_name:      REXML::XPath.first(element, 'config/name')&.text,
      scanner_name:     REXML::XPath.first(element, 'scanner/name')&.text,
      schedule_name:    REXML::XPath.first(element, 'schedule/name')&.text,
      alterable:        REXML::XPath.first(element, 'alterable')&.text == '1',
      auto_delete:      auto_delete,
      auto_delete_data: auto_delete ? keep : 5,
      hosts_ordering:   REXML::XPath.first(element, 'hosts_ordering')&.text || 'sequential',
      max_concurrency:  preference(element, 'max_checks')&.to_i,
      max_hosts:        preference(element, 'max_hosts')&.to_i,
    }
  end

  # The value of a task's scanner preference, or nil when gvmd lists none.
  def preference(element, scanner_name)
    REXML::XPath.first(element, "preferences/preference[scanner_name=\"#{scanner_name}\"]/value")&.text
  end

  def resolve_required(context, type, object_name, label)
    id = resolve_name_to_id(context, type, object_name)
    raise Puppet::ResourceError, "GVM #{label} not found: #{object_name}" unless id

    id
  end

  # The UUID of the target, config or scanner the task should use, or nil
  # when it is the one the task already uses.
  def changed_id(context, type, should, current)
    attribute = :"#{type}_name"
    wanted = should[attribute]
    (wanted == current[attribute]) ? nil : resolve_name_to_id(context, type, wanted)
  end

  def build_create_xml(name, should, ids)
    parts = [
      "<name>#{xe(name)}</name>",
      "<target id=\"#{ids[:target]}\"/>",
      "<config id=\"#{ids[:config]}\"/>",
      "<scanner id=\"#{ids[:scanner]}\"/>",
      "<alterable>#{should[:alterable] ? 1 : 0}</alterable>",
      "<hosts_ordering>#{xe(should[:hosts_ordering])}</hosts_ordering>",
    ]
    comment = should[:comment]
    schedule_id = ids[:schedule]
    parts << "<comment>#{xe(comment)}</comment>" if comment
    parts << "<schedule id=\"#{schedule_id}\"/>" if schedule_id
    parts << "<preferences>#{build_preferences_xml(should)}</preferences>"
    "<create_task>#{parts.join}</create_task>"
  end

  def build_modify_xml(id, should, ids)
    # target/config/scanner are only set when changed (see #update); gvmd
    # rejects them on a task that has already run.
    parts = ids.slice(:target, :config, :scanner).filter_map { |type, id_of_type| id_of_type && "<#{type} id=\"#{id_of_type}\"/>" }
    parts << "<alterable>#{should[:alterable] ? 1 : 0}</alterable>"
    parts << "<hosts_ordering>#{xe(should[:hosts_ordering])}</hosts_ordering>"
    # delete_properties clears the comment with an empty element; an unset
    # schedule_name already goes out as the empty schedule id below.
    parts << "<comment>#{xe(should[:comment])}</comment>" if should.key?(:comment) || deleting?(should, :comment)
    parts << "<schedule id=\"#{ids[:schedule]}\"/>"
    parts << "<preferences>#{build_preferences_xml(should)}</preferences>"
    "<modify_task task_id=\"#{id}\">#{parts.join}</modify_task>"
  end

  def build_preferences_xml(should)
    # gvmd stores 0 internally for "keep all reports" (auto-delete off), but
    # the API rejects setting auto_delete_data = 0 (valid range is 2–1200).
    # Omitting the preference on modify leaves it at gvmd's stored value; on
    # create gvmd defaults it to 0.  So we only send auto_delete_data when
    # auto_delete is enabled.
    preferences = {
      'auto_delete_data' => should[:auto_delete] && should[:auto_delete_data],
      'max_checks'       => should[:max_concurrency],
      'max_hosts'        => should[:max_hosts],
    }
    preferences.filter_map { |scanner_name, value|
      "<preference><scanner_name>#{scanner_name}</scanner_name><value>#{value}</value></preference>" if value
    }.join
  end
end
