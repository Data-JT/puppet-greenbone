# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_task'

RSpec.describe 'the gvm_task type' do
  let(:type) { Puppet::Type.type(:gvm_task) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'exposes the expected attributes' do
    [:ensure, :name, :target_name, :config_name, :schedule_name].each do |attr|
      expect(type.attrclass(attr)).not_to be_nil
    end
  end

  it 'constructs a valid resource' do
    expect {
      type.new(name: 'scan', target_name: 'net', config_name: 'Full and fast')
    }.not_to raise_error
  end
end
