# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_filter'

RSpec.describe 'the gvm_filter type' do
  let(:type) { Puppet::Type.type(:gvm_filter) }

  it 'is registered' do
    expect(type).not_to be_nil
  end

  it 'uses name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'defaults filter_type to result' do
    resource = type.new(name: 'f', term: 'apply_overrides=1')
    expect(resource[:filter_type]).to eq('result')
  end

  it 'rejects a filter_type that could break out of the XML element' do
    expect {
      type.new(name: 'f', term: 'x', filter_type: 'result</type>')
    }.to raise_error(Puppet::ResourceError)
  end
end
