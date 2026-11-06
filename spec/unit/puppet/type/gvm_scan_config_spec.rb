# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_scan_config'

RSpec.describe 'the gvm_scan_config type' do
  let(:type) { Puppet::Type.type(:gvm_scan_config) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'constructs a valid resource' do
    expect {
      type.new(
        name: 'Full and fast (custom)',
        base_config: 'Full and fast',
        scanner_preferences: { 'expand_vhosts' => '0' },
        nvt_preferences: [{ 'oid' => '1.3.6.1.4.1.25623.1.0.12288', 'id' => '18', 'type' => 'checkbox', 'name' => 'n', 'value' => 'yes' }],
      )
    }.not_to raise_error
  end

  it 'rejects an NVT preference missing its id' do
    expect {
      type.new(name: 'c', nvt_preferences: [{ 'oid' => '1.2.3', 'type' => 'checkbox', 'name' => 'n', 'value' => 'yes' }])
    }.to raise_error(Puppet::ResourceError)
  end

  it 'rejects an OID that could break out of the XML attribute' do
    expect {
      type.new(name: 'c', nvt_preferences: [{ 'oid' => '1.2"/><x', 'id' => '1', 'type' => 't', 'name' => 'n', 'value' => 'v' }])
    }.to raise_error(Puppet::ResourceError)
  end
end
