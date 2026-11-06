# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_schedule/gvm_schedule'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmSchedule::GvmSchedule do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }

  SAMPLE_ICAL = <<~ICAL
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Puppet Greenbone Profile//EN
    BEGIN:VEVENT
    DTSTART:20240101T000000Z
    RRULE:FREQ=DAILY
    END:VEVENT
    END:VCALENDAR
  ICAL

  def xml_doc(str)
    REXML::Document.new(str)
  end

  describe '#get' do
    it 'returns an empty array when transport_command returns nil' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'parses a schedule element' do
      doc = xml_doc(<<~XML)
        <get_schedules_response status="200">
          <schedule id="s1">
            <name>Daily Scan</name>
            <comment>every day</comment>
            <icalendar>#{SAMPLE_ICAL}</icalendar>
            <timezone>Europe/Berlin</timezone>
          </schedule>
        </get_schedules_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.length).to eq(1)
      expect(result[0]).to include(
        ensure: 'present',
        name: 'Daily Scan',
        comment: 'every day',
        timezone: 'Europe/Berlin',
      )
    end

    it 'defaults timezone to UTC when absent' do
      doc = xml_doc(<<~XML)
        <get_schedules_response status="200">
          <schedule id="s1">
            <name>S</name>
            <icalendar>#{SAMPLE_ICAL}</icalendar>
          </schedule>
        </get_schedules_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result[0][:timezone]).to eq('UTC')
    end
  end

  describe '#create' do
    it 'sends create_schedule XML with name, icalendar, and timezone' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<create_schedule>', '<name>Daily Scan</name>')
        expect(xml).to include('<timezone>UTC</timezone>')
        expect(xml).to include('VCALENDAR')
      end
      provider.create(context, 'Daily Scan', { icalendar: SAMPLE_ICAL, timezone: 'UTC' })
    end

    it 'includes comment when provided' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<comment>test</comment>')
      end
      provider.create(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'UTC', comment: 'test' })
    end
  end

  describe '#update' do
    before(:each) do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'schedule', 'S').and_return('sched-uuid')
    end

    it 'modifies by the resolved id, with name, icalendar and timezone' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to start_with('<modify_schedule schedule_id="sched-uuid"><name>S</name>')
        expect(xml).to include('<timezone>Europe/Berlin</timezone>', 'RRULE:FREQ=DAILY')
      end
      provider.update(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'Europe/Berlin' })
    end

    it 'leaves an undeclared comment alone' do
      expect(provider).to receive(:transport_command).with(context, satisfy { |xml| !xml.include?('<comment>') })
      provider.update(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'UTC' })
    end

    it 'sends a declared comment' do
      expect(provider).to receive(:transport_command).with(context, include('<comment>nightly</comment>'))
      provider.update(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'UTC', comment: 'nightly' })
    end

    it 'clears the comment with an empty element when delete_properties lists it' do
      expect(provider).to receive(:transport_command).with(context, include('<comment></comment>'))
      provider.update(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'UTC', delete_properties: ['comment'] })
    end

    it 'raises when the schedule has gone' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'schedule', 'S').and_return(nil)
      expect { provider.update(context, 'S', { icalendar: SAMPLE_ICAL, timezone: 'UTC' }) }
        .to raise_error(Puppet::ResourceError, %r{not found for update})
    end
  end

  describe '#delete' do
    it 'raises when schedule is not found' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.delete(context, 'Missing')
      }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end

    it 'sends delete_schedule XML with the resolved id' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'schedule', 'Daily Scan').and_return('sched-uuid')
      expect(provider).to receive(:transport_command).with(context, include('sched-uuid'))
      provider.delete(context, 'Daily Scan')
    end
  end

  describe '#normalize_ical (private)' do
    it 'strips UID, DTSTAMP, SUMMARY lines' do
      ical = "BEGIN:VCALENDAR\nUID:some-uid\nDTSTAMP:20240101T000000Z\nSUMMARY:test\nEND:VCALENDAR\n"
      result = provider.send(:normalize_ical, ical)
      expect(result).not_to include('UID:', 'DTSTAMP:', 'SUMMARY:')
      expect(result).to include('BEGIN:VCALENDAR', 'END:VCALENDAR')
    end

    it 'normalizes PRODID to the canonical Puppet value' do
      ical = "BEGIN:VCALENDAR\nPRODID:-//gvmd//NONSGML gvmd 22.4//EN\nEND:VCALENDAR\n"
      result = provider.send(:normalize_ical, ical)
      expect(result).to include('PRODID:-//Puppet Greenbone Profile//EN')
    end

    it 'strips the injected DURATION:PT0S line' do
      ical = "BEGIN:VCALENDAR\nDURATION:PT0S\nEND:VCALENDAR\n"
      result = provider.send(:normalize_ical, ical)
      expect(result).not_to include('DURATION:PT0S')
    end

    it 'normalises CRLF line endings to LF' do
      ical = "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n"
      result = provider.send(:normalize_ical, ical)
      expect(result).not_to include("\r")
    end

    it 'appends a trailing newline' do
      ical = "BEGIN:VCALENDAR\nEND:VCALENDAR"
      result = provider.send(:normalize_ical, ical)
      expect(result).to end_with("\n")
    end
  end
end
