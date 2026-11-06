# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_ldap'

RSpec.describe 'the gvm_ldap type' do
  let(:type) { Puppet::Type.type(:gvm_ldap) }

  it 'loads' do
    expect(type).not_to be_nil
  end

  it 'has name as the namevar' do
    expect(type.key_attributes).to eq([:name])
  end

  it 'exposes the expected attributes' do
    [:ensure, :name, :ldaphost, :authdn, :cacert, :allow_plaintext, :ldaps_only].each do |attr|
      expect(type.attrclass(attr)).not_to be_nil
    end
  end

  it 'constructs a valid resource' do
    expect {
      type.new(name: 'ldap_connect', ldaphost: 'ldap.example.org', authdn: 'uid=%s,dc=example,dc=org')
    }.not_to raise_error
  end

  it 'accepts a host with a port' do
    expect { type.new(name: 'ldap_connect', ldaphost: 'ldap.example.org:636') }.not_to raise_error
  end

  # gvm-libs prepends the scheme itself; a URI becomes ldap://ldaps://host.
  it 'rejects a URI as ldaphost' do
    expect { type.new(name: 'ldap_connect', ldaphost: 'ldaps://ldap.example.org') }.to raise_error(Puppet::ResourceError)
  end

  it 'rejects an authdn without exactly one %s' do
    expect { type.new(name: 'ldap_connect', authdn: 'uid=bob,dc=example,dc=org') }.to raise_error(Puppet::ResourceError)
    expect { type.new(name: 'ldap_connect', authdn: 'uid=%s,cn=%s,dc=x') }.to raise_error(Puppet::ResourceError)
  end

  it 'defaults ldaps_only to false' do
    expect(type.new(name: 'ldap_connect')[:ldaps_only].to_s).to eq('false')
  end
end
