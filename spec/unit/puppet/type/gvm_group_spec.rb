# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_group'

RSpec.describe 'the gvm_group type' do
  let(:type) { Puppet::Type.type(:gvm_group) }

  it 'uses name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'accepts a member list' do
    expect(type.new(name: 'g', users: ['admin'])[:users]).to eq(['admin'])
  end
end
