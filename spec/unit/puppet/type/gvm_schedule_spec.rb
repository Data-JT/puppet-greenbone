# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_schedule'

RSpec.describe 'the gvm_schedule type' do
  let(:type) { Puppet::Type.type(:gvm_schedule) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'exposes ensure and name attributes' do
    [:ensure, :name].each do |attr|
      expect(type.attrclass(attr)).not_to be_nil
    end
  end

  it 'constructs a valid resource' do
    expect { type.new(name: 'weekly') }.not_to raise_error
  end
end
