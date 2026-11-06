# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_permission/gvm_permission'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmPermission::GvmPermission do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  let(:pid) { '5e82018c-4838-4a33-8d2b-c345b858724a' }
  let(:uid) { '5f5d96ad-4a8e-4ab8-b611-7b0ab65e90cf' }
  let(:gid) { '982645dd-4269-435d-9d7d-8a5ddfcf4c8e' }

  # Shape captured from gvmd 26.42 on 2026-10-20: one built-in permission
  # (no resource, empty comment) and one managed Super grant.
  let(:listing) do
    REXML::Document.new(<<~XML)
      <get_permissions_response status="200">
        <permission id="0b6d64f5-db4d-4471-8ee0-b53762982c7a"><owner><name/></owner><name>authenticate</name><comment/>
          <resource id=""><name/><type/></resource>
          <subject id="5f8fd16c-c550-11e3-b6ab-406186ea4fc5"><name>Info</name><type>role</type></subject></permission>
        <permission id="#{pid}"><owner><name>admin</name></owner><name>Super</name>
          <comment>Why.

      [puppet:alice-super]</comment>
          <resource id="#{gid}"><name>Shared</name><type>group</type></resource>
          <subject id="#{uid}"><name>alice</name><type>user</type></subject></permission>
        <filters id=""><term>first=1 rows=10 sort=name</term></filters>
      </get_permissions_response>
    XML
  end

  let(:should_hash) do
    { permission: 'Super', subject_type: 'user', subject_name: 'alice',
      resource_type: 'group', resource_name: 'Shared', comment: 'Why.' }
  end

  describe '#get' do
    it 'returns only marked permissions, with names from the response' do
      allow(provider).to receive(:transport_command).and_return(listing)
      expect(provider.get(context)).to eq([{
                                            ensure: 'present', name: 'alice-super', permission: 'Super',
                                            subject_type: 'user', subject_name: 'alice',
                                            resource_type: 'group', resource_name: 'Shared', comment: 'Why.',
                                          }])
    end

    it 'asks for every permission; ~270 built-ins come before any managed one' do
      expect(provider).to receive(:transport_command).with(context, '<get_permissions filter="rows=-1"/>').and_return(nil)
      provider.get(context)
    end
  end

  describe '#canonicalize' do
    it 'spells permissions the way gvmd stores them' do
      out = provider.canonicalize(context, [{ name: 'a', permission: 'super' }, { name: 'b', permission: 'GET_Tasks' }])
      expect(out.map { |r| r[:permission] }).to eq(['Super', 'get_tasks'])
    end
  end

  describe '#create' do
    before(:each) do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'user', 'alice').and_return(uid)
      allow(provider).to receive(:resolve_name_to_id).with(context, 'group', 'Shared').and_return(gid)
    end

    it 'sends subject and resource by resolved id, with the marker in the comment' do
      expect(provider).to receive(:transport_command).with(
        context,
        "<create_permission><name>Super</name><comment>Why.\n\n[puppet:alice-super]</comment>" \
        "<subject id=\"#{uid}\"><type>user</type></subject>" \
        "<resource id=\"#{gid}\"><type>group</type></resource></create_permission>",
      )
      provider.create(context, 'alice-super', should_hash)
    end

    it 'omits the resource when none is given' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).not_to include('<resource')
        expect(xml).to include('<comment>[puppet:alice-all]</comment>')
      end
      provider.create(context, 'alice-all', { permission: 'get_tasks', subject_type: 'user', subject_name: 'alice' })
    end

    it 'raises when the subject does not exist' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'user', 'nobody').and_return(nil)
      expect { provider.create(context, 'x', should_hash.merge(subject_name: 'nobody')) }
        .to raise_error(Puppet::ResourceError, %r{user not found: nobody})
    end

    it 'raises when only half of the resource is given' do
      expect { provider.create(context, 'x', should_hash.merge(resource_name: nil)) }
        .to raise_error(Puppet::ResourceError, %r{together})
    end
  end

  describe '#update / #delete' do
    before(:each) do
      allow(provider).to receive(:resolve_name_to_id).and_return(uid)
    end

    it 'finds the permission by marker and modifies it' do
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        xml.start_with?('<get_permissions') ? listing : nil
      end
      provider.update(context, 'alice-super', should_hash)
      expect(sent.last).to start_with("<modify_permission permission_id=\"#{pid}\"><name>Super</name>")
    end

    # The marker stays: it is what identifies the permission on the next run.
    it 'clears the comment down to the bare marker when delete_properties lists it' do
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        xml.start_with?('<get_permissions') ? listing : nil
      end
      provider.update(context, 'alice-super', should_hash.except(:comment).merge(delete_properties: ['comment']))
      expect(sent.last).to include('<comment>[puppet:alice-super]</comment>')
    end

    it 'deletes by marker' do
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        xml.start_with?('<get_permissions') ? listing : nil
      end
      provider.delete(context, 'alice-super')
      expect(sent.last).to eq("<delete_permission permission_id=\"#{pid}\" ultimate=\"1\"/>")
    end

    it 'never touches an unmarked permission' do
      allow(provider).to receive(:transport_command).and_return(listing)
      expect { provider.delete(context, 'authenticate') }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end
  end
end
