# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_target/gvm_target'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmTarget::GvmTarget do
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

    it 'parses a target element into a resource hash' do
      doc = xml_doc(<<~XML)
        <get_targets_response status="200">
          <target id="abc-uuid">
            <name>My Target</name>
            <comment>A test target</comment>
            <hosts>192.0.2.0/24</hosts>
            <exclude_hosts>192.0.2.5</exclude_hosts>
            <port_list id="port-uuid"><name>All IANA assigned TCP</name></port_list>
            <alive_tests>ICMP Ping</alive_tests>
            <allow_simultaneous_ips>1</allow_simultaneous_ips>
            <reverse_lookup_only>0</reverse_lookup_only>
            <reverse_lookup_unify>1</reverse_lookup_unify>
          </target>
        </get_targets_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.length).to eq(1)
      expect(result[0]).to include(
        ensure: 'present',
        name: 'My Target',
        comment: 'A test target',
        hosts: '192.0.2.0/24',
        exclude_hosts: '192.0.2.5',
        port_list_name: 'All IANA assigned TCP',
        alive_test: 'ICMP Ping',
        allow_simultaneous_ips: true,
        reverse_lookup_only: false,
        reverse_lookup_unify: true,
      )
    end

    it 'returns multiple targets' do
      doc = xml_doc(<<~XML)
        <get_targets_response status="200">
          <target id="id1"><name>T1</name><hosts>h1</hosts>
            <port_list id="p1"><name>List A</name></port_list>
            <allow_simultaneous_ips>0</allow_simultaneous_ips>
            <reverse_lookup_only>0</reverse_lookup_only>
            <reverse_lookup_unify>0</reverse_lookup_unify>
          </target>
          <target id="id2"><name>T2</name><hosts>h2</hosts>
            <port_list id="p2"><name>List B</name></port_list>
            <allow_simultaneous_ips>1</allow_simultaneous_ips>
            <reverse_lookup_only>0</reverse_lookup_only>
            <reverse_lookup_unify>0</reverse_lookup_unify>
          </target>
        </get_targets_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.map { |r| r[:name] }).to eq(['T1', 'T2'])
    end
  end

  describe '#create' do
    it 'resolves port_list_name and sends create_target XML' do
      allow(provider).to receive(:resolve_name_to_id)
        .with(context, 'port_list', 'All IANA assigned TCP').and_return('port-uuid')
      expect(provider).to receive(:transport_command)
        .with(context, include('<create_target>'))
      provider.create(context, 'New Target', { hosts: '192.0.2.1', port_list_name: 'All IANA assigned TCP' })
    end

    it 'raises when port list is not found' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.create(context, 'T', { hosts: 'h', port_list_name: 'Missing' })
      }.to raise_error(Puppet::ResourceError, %r{port list not found})
    end
  end

  describe '#canonicalize' do
    it 'normalises host lists the way gvmd stores them' do
      r = provider.canonicalize(context, [{ name: 'T', hosts: "198.51.100.0/24,203.0.113.0/24\n 198.51.100.0/24,", exclude_hosts: ' ' }]).first
      expect(r[:hosts]).to eq('198.51.100.0/24, 203.0.113.0/24')
      expect(r[:exclude_hosts]).to be_nil
    end

    it 'leaves absent keys absent' do
      expect(provider.canonicalize(context, [{ name: 'T' }]).first).to eq(name: 'T')
    end
  end

  describe '#update' do
    let(:id) { '11111111-2222-3333-4444-555555555555' }
    # A target as gvmd returns it for get_targets: hosts normalised to ", ".
    let(:current) do
      xml_doc(<<~XML)
        <get_targets_response status="200">
          <target id="#{id}">
            <name>T</name>
            <comment>old</comment>
            <hosts>198.51.100.0/24, 203.0.113.0/24</hosts>
            <exclude_hosts></exclude_hosts>
            <port_list id="p1"><name>All IANA assigned TCP</name></port_list>
            <alive_tests>ICMP Ping</alive_tests>
            <allow_simultaneous_ips>1</allow_simultaneous_ips>
            <reverse_lookup_only>0</reverse_lookup_only>
            <reverse_lookup_unify>0</reverse_lookup_unify>
          </target>
        </get_targets_response>
      XML
    end
    let(:desired) do
      {
        name: 'T', ensure: 'present', comment: 'old', hosts: '198.51.100.0/24,203.0.113.0/24',
        port_list_name: 'All IANA assigned TCP', alive_test: 'ICMP Ping',
        allow_simultaneous_ips: true, reverse_lookup_only: false, reverse_lookup_unify: false
      }
    end

    before(:each) do
      allow(provider).to receive(:transport_command)
        .with(context, include('<get_targets ')).and_return(current)
    end

    it 'raises when target is not found for update' do
      allow(provider).to receive(:transport_command)
        .with(context, include('<get_targets ')).and_return(xml_doc('<get_targets_response status="200"/>'))
      expect {
        provider.update(context, 'T', { hosts: 'h', port_list_name: 'L' })
      }.to raise_error(Puppet::ResourceError, %r{not found for update})
    end

    # The bug this replaces: every attribute was sent, and gvmd refuses
    # hosts/port_list/flags on a target a task uses even when unchanged.
    it 'sends only the comment when only the comment changed' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><comment>new</comment></modify_target>")
      provider.update(context, 'T', desired.merge(comment: 'new'))
    end

    it 'sends only alive_tests when only the alive test changed' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><alive_tests>Consider Alive</alive_tests></modify_target>")
      provider.update(context, 'T', desired.merge(alive_test: 'Consider Alive'))
    end

    it 'sends hosts together with exclude_hosts when hosts changed' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><hosts>192.0.2.0/24</hosts><exclude_hosts></exclude_hosts></modify_target>")
      provider.update(context, 'T', desired.merge(hosts: '192.0.2.0/24'))
    end

    it 'sends hosts together with exclude_hosts when only exclude_hosts changed' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><hosts>198.51.100.0/24,203.0.113.0/24</hosts><exclude_hosts>198.51.100.5</exclude_hosts></modify_target>")
      provider.update(context, 'T', desired.merge(exclude_hosts: '198.51.100.5'))
    end

    it 'resolves and sends the port list only when it changed' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'port_list', 'All TCP').and_return('p2')
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><port_list id=\"p2\"/></modify_target>")
      provider.update(context, 'T', desired.merge(port_list_name: 'All TCP'))
    end

    it 'raises when a changed port list is not found' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'port_list', 'Missing').and_return(nil)
      expect {
        provider.update(context, 'T', desired.merge(port_list_name: 'Missing'))
      }.to raise_error(Puppet::ResourceError, %r{port list not found})
    end

    it 'sends a changed flag alone' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><reverse_lookup_unify>1</reverse_lookup_unify></modify_target>")
      provider.update(context, 'T', desired.merge(reverse_lookup_unify: true))
    end

    it 'sends nothing when the target already matches' do
      expect(provider).not_to receive(:transport_command).with(context, include('<modify_target'))
      expect(provider).not_to receive(:resolve_name_to_id)
      provider.update(context, 'T', desired)
    end

    it 'leaves an undeclared comment alone' do
      expect(provider).not_to receive(:transport_command).with(context, include('<modify_target'))
      provider.update(context, 'T', desired.except(:comment))
    end

    it 'clears the comment with an empty element when delete_properties lists it' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_target target_id=\"#{id}\"><comment></comment></modify_target>")
      provider.update(context, 'T', desired.except(:comment).merge(delete_properties: ['comment']))
    end

    context 'with exclude_hosts stored' do
      let(:current) do
        xml_doc(<<~XML)
          <get_targets_response status="200">
            <target id="#{id}">
              <name>T</name>
              <hosts>198.51.100.0/24, 203.0.113.0/24</hosts>
              <exclude_hosts>198.51.100.5</exclude_hosts>
              <port_list id="p1"><name>All IANA assigned TCP</name></port_list>
              <alive_tests>ICMP Ping</alive_tests>
              <allow_simultaneous_ips>1</allow_simultaneous_ips>
              <reverse_lookup_only>0</reverse_lookup_only>
              <reverse_lookup_unify>0</reverse_lookup_unify>
            </target>
          </get_targets_response>
        XML
      end

      it 'clears exclude_hosts with an empty element, sent with hosts as gvmd requires' do
        expect(provider).to receive(:transport_command)
          .with(context, "<modify_target target_id=\"#{id}\"><hosts>198.51.100.0/24,203.0.113.0/24</hosts><exclude_hosts></exclude_hosts></modify_target>")
        provider.update(context, 'T', desired.except(:comment).merge(delete_properties: ['exclude_hosts']))
      end
    end
  end

  describe '#delete' do
    it 'resolves name to id and sends delete XML containing the id' do
      allow(provider).to receive(:resolve_name_to_id)
        .with(context, 'target', 'My Target').and_return('target-uuid')
      expect(provider).to receive(:transport_command)
        .with(context, include('target-uuid'))
      provider.delete(context, 'My Target')
    end

    it 'raises when target is not found' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.delete(context, 'Missing')
      }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end
  end

  describe '#build_create_xml (private)' do
    it 'includes name, hosts, port_list, and closing tag' do
      xml = provider.send(:build_create_xml, 'T', { hosts: '192.0.2.1' }, 'pid')
      expect(xml).to include('<create_target>', '<name>T</name>', '<hosts>192.0.2.1</hosts>',
                             '<port_list id="pid"/>', '</create_target>')
    end

    it 'includes optional comment when provided' do
      xml = provider.send(:build_create_xml, 'T', { hosts: 'h', comment: 'hi' }, 'pid')
      expect(xml).to include('<comment>hi</comment>')
    end

    it 'omits comment when not provided' do
      xml = provider.send(:build_create_xml, 'T', { hosts: 'h' }, 'pid')
      expect(xml).not_to include('<comment>')
    end

    it 'XML-escapes the target name' do
      xml = provider.send(:build_create_xml, 'A<B>&C', { hosts: 'h' }, 'pid')
      expect(xml).to include('<name>A&lt;B&gt;&amp;C</name>')
    end
  end
end
