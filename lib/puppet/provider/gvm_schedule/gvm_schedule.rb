# frozen_string_literal: true

require_relative '../gvm_base_provider'

# @api private
module Puppet::Provider::GvmSchedule; end

# Provider for gvm_schedule resources via the GMP Unix socket.
class Puppet::Provider::GvmSchedule::GvmSchedule < Puppet::Provider::GvmBaseProvider
  def get(context)
    # rows=-1 is load-bearing. GMP pages list responses and defaults to TEN
    # rows, so without it this provider sees only the first ten schedules and
    # reports every one after that as absent. Puppet then tries to CREATE an
    # object that exists ("GMP error 400: ... exists already") and, for an
    # entry set to ensure=absent, does nothing at all while reporting success.
    # Both were observed on a production gvmd on 2026-08-20, at exactly the point
    # the instance grew past ten schedules.
    response = transport_command(context, '<get_schedules filter="rows=-1"/>')
    return [] unless response

    load_rexml_xpath
    REXML::XPath.match(response, '//schedule').map do |el|
      {
        ensure:    'present',
        name:      REXML::XPath.first(el, 'name')&.text,
        comment:   REXML::XPath.first(el, 'comment')&.text,
        icalendar: normalize_ical(REXML::XPath.first(el, 'icalendar')&.text.to_s.strip),
        timezone:  REXML::XPath.first(el, 'timezone')&.text || 'UTC',
      }
    end
  end

  def create(context, name, should)
    context.notice("Creating GVM schedule '#{name}'")
    xml = '<create_schedule>' \
          "<name>#{xe(name)}</name>" \
          "<icalendar>#{xe(should[:icalendar])}</icalendar>" \
          "<timezone>#{xe(should[:timezone])}</timezone>" \
          "#{comment_xml(should)}" \
          '</create_schedule>'
    transport_command(context, xml)
  end

  def update(context, name, should)
    context.notice("Updating GVM schedule '#{name}'")
    id = resolve_name_to_id(context, 'schedule', name)
    raise Puppet::ResourceError, "GVM schedule not found for update: #{name}" unless id

    xml = "<modify_schedule schedule_id=\"#{id}\">" \
          "<name>#{xe(name)}</name>" \
          "<icalendar>#{xe(should[:icalendar])}</icalendar>" \
          "<timezone>#{xe(should[:timezone])}</timezone>" \
          "#{comment_xml(should)}" \
          '</modify_schedule>'
    transport_command(context, xml)
  end

  def delete(context, name)
    context.notice("Deleting GVM schedule '#{name}'")
    id = resolve_name_to_id(context, 'schedule', name)
    raise Puppet::ResourceError, "GVM schedule not found for delete: #{name}" unless id

    transport_command(context, "<delete_schedule schedule_id=\"#{id}\" ultimate=\"1\"/>")
  end

  private

  # Sent when the manifest declares a comment, and empty to clear it through
  # delete_properties. An undeclared comment is left as gvmd holds it (on
  # create, gvmd's default).
  def comment_xml(should)
    return '' unless should.key?(:comment) || deleting?(should, :comment)

    "<comment>#{xe(should[:comment])}</comment>"
  end

  # Normalize the iCal returned by gvmd so it compares equal to the
  # Puppet-desired value.  gvmd does not round-trip all iCal properties:
  #   - PRODID: replaced with its own value on every save → normalize to
  #             the canonical Puppet value (same value used in the manifest)
  #   - UID, DTSTAMP: injected on every save → stripped
  #   - DURATION:PT0S: injected when no duration specified → stripped
  #   - SUMMARY: silently dropped → stripped (manifest must omit it too)
  # A trailing newline is appended to match YAML literal-block-scalar output.
  def normalize_ical(ical)
    ical.to_s.gsub("\r\n", "\n").lines.map(&:chomp)
        .map    { |line| line.start_with?('PRODID:') ? 'PRODID:-//Puppet Greenbone Profile//EN' : line }
        .reject { |line| line.start_with?('UID:', 'DTSTAMP:', 'SUMMARY:') || line == 'DURATION:PT0S' }
        .join("\n") + "\n"
  end
end
