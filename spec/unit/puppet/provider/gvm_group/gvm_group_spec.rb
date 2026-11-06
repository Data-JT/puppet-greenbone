# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_group/gvm_group'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmGroup::GvmGroup do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  let(:id) { '982645dd-4269-435d-9d7d-8a5ddfcf4c8e' }

  it 'reads groups, splitting the comma-separated member list' do
    # Shape captured from gvmd 26.42 on 2026-10-20, trimmed.
    doc = REXML::Document.new(<<~XML)
      <get_groups_response status="200">
        <group id="#{id}"><owner><name>admin</name></owner><name>Shared</name><comment>c</comment><users>bob,admin</users></group>
        <filters id=""><term>first=1 rows=10 sort=name</term></filters>
      </get_groups_response>
    XML
    allow(provider).to receive(:transport_command).and_return(doc)
    expect(provider.get(context)).to eq([{ ensure: 'present', name: 'Shared', users: ['admin', 'bob'], comment: 'c' }])
  end

  it 'reads an empty group as no members' do
    doc = REXML::Document.new(%(<get_groups_response status="200"><group id="#{id}"><name>E</name><comment/><users></users></group></get_groups_response>))
    allow(provider).to receive(:transport_command).and_return(doc)
    expect(provider.get(context).first).to include(users: [], comment: nil)
  end

  it 'canonicalizes members as a sorted set' do
    r = provider.canonicalize(context, [{ name: 'g', users: ['bob', ' admin', 'bob', ''] }]).first
    expect(r[:users]).to eq(['admin', 'bob'])
  end

  it 'creates with a comma-joined member list' do
    expect(provider).to receive(:transport_command)
      .with(context, '<create_group><name>Shared</name><comment></comment><users>admin,bob</users></create_group>')
    provider.create(context, 'Shared', { users: ['bob', 'admin'] })
  end

  it 'always sends <users> on modify, so an emptied list empties the group' do
    allow(provider).to receive(:resolve_name_to_id).with(context, 'group', 'Shared').and_return(id)
    expect(provider).to receive(:transport_command)
      .with(context, "<modify_group group_id=\"#{id}\"><name>Shared</name><comment>c</comment><users></users></modify_group>")
    provider.update(context, 'Shared', { users: [], comment: 'c' })
  end

  it 'clears the comment with an empty element when delete_properties lists it' do
    allow(provider).to receive(:resolve_name_to_id).with(context, 'group', 'Shared').and_return(id)
    expect(provider).to receive(:transport_command)
      .with(context, "<modify_group group_id=\"#{id}\"><name>Shared</name><comment></comment><users>admin</users></modify_group>")
    provider.update(context, 'Shared', { users: ['admin'], delete_properties: ['comment'] })
  end

  it 'deletes ultimately by id' do
    allow(provider).to receive(:resolve_name_to_id).and_return(id)
    expect(provider).to receive(:transport_command).with(context, "<delete_group group_id=\"#{id}\" ultimate=\"1\"/>")
    provider.delete(context, 'Shared')
  end
end
