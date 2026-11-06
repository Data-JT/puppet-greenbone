# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_task/gvm_task'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmTask::GvmTask do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }

  def xml_doc(str)
    REXML::Document.new(str)
  end

  describe '#get' do
    it 'returns an empty array when transport_command returns nil' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'parses a task with auto_delete off (auto_delete_data = 0 → defaults to 5)' do
      doc = xml_doc(<<~XML)
        <get_tasks_response status="200">
          <task id="t1">
            <name>Nightly Scan</name>
            <comment>prod</comment>
            <target><name>Servers</name></target>
            <config><name>Full and Fast</name></config>
            <scanner><name>OpenVAS Default</name></scanner>
            <schedule><name>Daily</name></schedule>
            <alterable>0</alterable>
            <hosts_ordering>sequential</hosts_ordering>
            <preferences>
              <preference>
                <scanner_name>auto_delete_data</scanner_name>
                <value>0</value>
              </preference>
              <preference>
                <scanner_name>max_checks</scanner_name>
                <value>4</value>
              </preference>
              <preference>
                <scanner_name>max_hosts</scanner_name>
                <value>4</value>
              </preference>
            </preferences>
          </task>
        </get_tasks_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.length).to eq(1)
      expect(result[0]).to include(
        ensure: 'present',
        name: 'Nightly Scan',
        comment: 'prod',
        target_name: 'Servers',
        config_name: 'Full and Fast',
        scanner_name: 'OpenVAS Default',
        schedule_name: 'Daily',
        alterable: false,
        auto_delete: false,
        auto_delete_data: 5,
        hosts_ordering: 'sequential',
        max_concurrency: 4,
        max_hosts: 4,
      )
    end

    it 'parses a task with auto_delete on (auto_delete_data = 10)' do
      doc = xml_doc(<<~XML)
        <get_tasks_response status="200">
          <task id="t2">
            <name>Weekly</name>
            <alterable>1</alterable>
            <hosts_ordering>random</hosts_ordering>
            <target><name>DMZ</name></target>
            <config><name>Discovery</name></config>
            <scanner><name>CVE</name></scanner>
            <preferences>
              <preference>
                <scanner_name>auto_delete_data</scanner_name>
                <value>10</value>
              </preference>
            </preferences>
          </task>
        </get_tasks_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result[0]).to include(
        auto_delete: true,
        auto_delete_data: 10,
        alterable: true,
        hosts_ordering: 'random',
      )
    end
  end

  describe '#create' do
    it 'raises when target is not found' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'target', 'T').and_return(nil)
      allow(provider).to receive(:resolve_name_to_id).with(context, 'config', anything).and_return('cid')
      allow(provider).to receive(:resolve_name_to_id).with(context, 'scanner', anything).and_return('sid')
      expect {
        provider.create(context, 'Task', { target_name: 'T', config_name: 'C', scanner_name: 'S' })
      }.to raise_error(Puppet::ResourceError, %r{GVM target not found})
    end

    it 'sends create_task XML with resolved ids' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'target', 'Servers').and_return('tid')
      allow(provider).to receive(:resolve_name_to_id).with(context, 'config', 'Full and Fast').and_return('cid')
      allow(provider).to receive(:resolve_name_to_id).with(context, 'scanner', 'OpenVAS').and_return('sid')
      expect(provider).to receive(:transport_command)
        .with(context, include('<create_task>'))
      provider.create(context, 'T', {
                        target_name: 'Servers', config_name: 'Full and Fast', scanner_name: 'OpenVAS',
        alterable: false, hosts_ordering: 'sequential',
                      })
    end
  end

  describe '#update' do
    let(:current) do
      {
        name: 'T', target_name: 'Servers', config_name: 'Full and Fast',
        scanner_name: 'OpenVAS', schedule_name: nil
      }
    end

    before(:each) do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'task', 'T').and_return('task-uuid')
      allow(provider).to receive(:get).with(context).and_return([current])
    end

    it 'omits target/config/scanner when unchanged (allows editing a task that has already run)' do
      should = current.merge(alterable: false, hosts_ordering: 'sequential', max_hosts: 4)
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        # Match the reference elements exactly: a bare '<scanner' would also
        # match the <scanner_name> of every task preference asserted below.
        expect(xml).not_to include('<target id=')
        expect(xml).not_to include('<config id=')
        expect(xml).not_to include('<scanner id=')
        expect(xml).to include('<scanner_name>max_hosts</scanner_name><value>4</value>')
      end
      provider.update(context, 'T', should)
    end

    it 'includes scanner when scanner_name changed' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'scanner', 'CVE').and_return('sid')
      should = current.merge(scanner_name: 'CVE', alterable: false, hosts_ordering: 'sequential')
      expect(provider).to receive(:transport_command).with(context, include('<scanner id="sid"/>'))
      provider.update(context, 'T', should)
    end

    it 'leaves an undeclared comment alone' do
      expect(provider).to receive(:transport_command).with(context, satisfy { |xml| !xml.include?('<comment>') })
      provider.update(context, 'T', current.merge(alterable: false, hosts_ordering: 'sequential'))
    end

    it 'clears the comment with an empty element when delete_properties lists it' do
      should = current.merge(alterable: false, hosts_ordering: 'sequential', delete_properties: ['comment'])
      expect(provider).to receive(:transport_command).with(context, include('<comment></comment>'))
      provider.update(context, 'T', should)
    end

    it 'sends the empty schedule id for a task without schedule_name, which clears it' do
      should = current.merge(alterable: false, hosts_ordering: 'sequential', delete_properties: ['schedule_name'])
      expect(provider).not_to receive(:resolve_name_to_id).with(context, 'schedule', anything)
      expect(provider).to receive(:transport_command).with(context, include('<schedule id=""/>'))
      provider.update(context, 'T', should)
    end

    it 'sends the resolved schedule id when schedule_name is set' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'schedule', 'Nightly').and_return('sched-uuid')
      should = current.merge(alterable: false, hosts_ordering: 'sequential', schedule_name: 'Nightly')
      expect(provider).to receive(:transport_command).with(context, include('<schedule id="sched-uuid"/>'))
      provider.update(context, 'T', should)
    end
  end

  describe '#delete' do
    it 'raises when task is not found' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.delete(context, 'Missing Task')
      }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end

    it 'sends delete_task XML with the resolved id' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'task', 'T').and_return('task-uuid')
      expect(provider).to receive(:transport_command).with(context, include('task-uuid'))
      provider.delete(context, 'T')
    end
  end

  describe '#build_preferences_xml (private)' do
    it 'includes auto_delete_data preference when auto_delete is true' do
      xml = provider.send(:build_preferences_xml, { auto_delete: true, auto_delete_data: 7 })
      expect(xml).to include('<scanner_name>auto_delete_data</scanner_name><value>7</value>')
    end

    it 'omits auto_delete_data when auto_delete is false' do
      xml = provider.send(:build_preferences_xml, { auto_delete: false, auto_delete_data: 5 })
      expect(xml).not_to include('auto_delete_data')
    end

    it 'includes max_checks preference when max_concurrency is set' do
      xml = provider.send(:build_preferences_xml, { max_concurrency: 4 })
      expect(xml).to include('<scanner_name>max_checks</scanner_name><value>4</value>')
    end

    it 'includes max_hosts preference when max_hosts is set' do
      xml = provider.send(:build_preferences_xml, { max_hosts: 4 })
      expect(xml).to include('<scanner_name>max_hosts</scanner_name><value>4</value>')
    end

    it 'omits max_hosts preference when max_hosts is unset' do
      xml = provider.send(:build_preferences_xml, { max_concurrency: 4 })
      expect(xml).not_to include('max_hosts')
    end
  end
end
