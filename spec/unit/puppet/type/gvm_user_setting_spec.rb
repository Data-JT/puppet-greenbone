# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_user_setting'

# resource_api requires ensure to be Enum[present, absent]; GMP settings cannot
# actually be deleted, so the *provider's* delete raises if absent is requested
# (covered in the provider spec). Here we just exercise the type definition.
RSpec.describe 'the gvm_user_setting type' do
  let(:type) { Puppet::Type.type(:gvm_user_setting) }

  it 'is registered' do
    expect(type).not_to be_nil
  end

  it 'can be instantiated with name and value' do
    resource = type.new(name: 'Timezone', value: 'Europe/Berlin')
    expect(resource[:name]).to eq('Timezone')
    expect(resource[:value]).to eq('Europe/Berlin')
  end

  it 'defaults ensure to present' do
    resource = type.new(name: 'Timezone', value: 'UTC')
    expect(resource[:ensure].to_s).to eq('present')
  end

  it 'uses name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end
end
