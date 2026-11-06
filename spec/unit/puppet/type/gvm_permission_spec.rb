# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_permission'

RSpec.describe 'the gvm_permission type' do
  let(:type) { Puppet::Type.type(:gvm_permission) }

  it 'uses name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'accepts a Super grant on a group' do
    expect {
      type.new(name: 'p', permission: 'Super', subject_type: 'user', subject_name: 'alice',
               resource_type: 'group', resource_name: 'Shared')
    }.not_to raise_error
  end

  it 'rejects a subject type gvmd does not have' do
    expect {
      type.new(name: 'p', permission: 'Super', subject_type: 'host', subject_name: 'x')
    }.to raise_error(Puppet::ResourceError)
  end

  it 'rejects a permission name that could break out of the XML element' do
    expect {
      type.new(name: 'p', permission: 'Super</name>', subject_type: 'user', subject_name: 'x')
    }.to raise_error(Puppet::ResourceError)
  end
end
