# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_target'

RSpec.describe 'the gvm_target type' do
  let(:type) { Puppet::Type.type(:gvm_target) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'exposes the expected attributes' do
    [:ensure, :name, :hosts, :port_list_name].each do |attr|
      expect(type.attrclass(attr)).not_to be_nil
    end
  end

  it 'constructs a valid resource' do
    expect {
      type.new(name: 'net', hosts: '192.0.2.0/24', port_list_name: 'All IANA assigned TCP')
    }.not_to raise_error
  end
end
