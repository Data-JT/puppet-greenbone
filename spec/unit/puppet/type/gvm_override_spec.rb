# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_override'

RSpec.describe 'the gvm_override type' do
  let(:type) { Puppet::Type.type(:gvm_override) }
  let(:base) { { name: 'fp-ssh-banner', nvt_oid: '1.3.6.1.4.1.25623.1.0.10267', text: 'Assessed: banner only.' } }

  it 'uses name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'constructs a valid resource' do
    expect { type.new(base.merge(hosts: '192.0.2.10', port: '22/tcp', severity: 5.0)) }.not_to raise_error
  end

  # The schema carries no `default:` (puppet-strings cannot parse -1), so the
  # provider's canonicalize supplies it. It must still be a managed value.
  it 'defaults new_severity to -1 (False Positive)' do
    expect(type.new(base)[:new_severity]).to eq(-1)
  end

  it 'keeps a declared new_severity' do
    expect(type.new(base.merge(new_severity: 0))[:new_severity]).to eq(0)
  end

  it 'defaults active to true' do
    # The RAL stores Boolean properties as symbols.
    expect(type.new(base)[:active]).to eq(:true)
  end

  it 'rejects an OID that could break out of the XML attribute' do
    expect { type.new(base.merge(nvt_oid: '1.2"/><x a="')) }.to raise_error(Puppet::ResourceError)
  end

  it 'rejects a non-numeric severity' do
    expect { type.new(base.merge(severity: 'high')) }.to raise_error(Puppet::ResourceError)
  end
end
