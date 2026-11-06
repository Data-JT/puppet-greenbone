# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_user'

RSpec.describe 'the gvm_user type' do
  let(:type) { Puppet::Type.type(:gvm_user) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'exposes the expected attributes' do
    [:ensure, :name, :password, :role_name, :source].each do |attr|
      expect(type.attrclass(attr)).not_to be_nil
    end
  end

  it 'constructs a valid resource' do
    expect { type.new(name: 'alice', role_name: 'User') }.not_to raise_error
  end
end
