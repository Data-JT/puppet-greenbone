# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_admin'

RSpec.describe 'the gvm_admin type' do
  let(:type) { Puppet::Type.type(:gvm_admin) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'constructs a valid resource' do
    expect { type.new(name: 'admin', password: 'secret') }.not_to raise_error
  end

  it 'rejects a username containing a space' do
    expect { type.new(name: 'bad name') }.to raise_error(Puppet::Error, %r{invalid characters})
  end

  it 'rejects a username containing angle brackets' do
    expect { type.new(name: 'a<b') }.to raise_error(Puppet::Error, %r{invalid characters})
  end

  it 'rejects an empty username' do
    expect { type.new(name: '   ') }.to raise_error(Puppet::Error, %r{non-empty})
  end

  it 'rejects a relative gvmd_bin path' do
    expect {
      type.new(name: 'admin', gvmd_bin: 'relative/gvmd')
    }.to raise_error(Puppet::Error, %r{absolute path})
  end

  it 'accepts an absolute gvmd_bin path' do
    expect {
      type.new(name: 'admin', gvmd_bin: '/usr/sbin/gvmd')
    }.not_to raise_error
  end

  it 'marks password as sensitive' do
    expect(type.new(name: 'admin', password: 'secret').parameter(:password).sensitive).to be(true)
  end

  describe 'ensure' do
    let(:resource) { type.new(name: 'admin', password: 'secret', ensure: 'present') }
    let(:provider) { resource.provider }

    it 'reads present or absent from the provider' do
      allow(provider).to receive(:exists?).and_return(true, false)
      expect(resource.property(:ensure).retrieve).to eq(:present)
      expect(resource.property(:ensure).retrieve).to eq(:absent)
    end

    it 'creates the user when present is wanted' do
      expect(provider).to receive(:create)
      resource.property(:ensure).sync
    end

    it 'deletes the user when absent is wanted' do
      absent = type.new(name: 'admin', ensure: 'absent')
      expect(absent.provider).to receive(:destroy)
      absent.property(:ensure).sync
    end
  end
end
