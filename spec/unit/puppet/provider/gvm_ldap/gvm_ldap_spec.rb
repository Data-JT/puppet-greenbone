# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_ldap/gvm_ldap'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmLdap::GvmLdap do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  # describe_auth as gvmd 26.42 answers it on a fresh install (captured from a
  # live gvmd 2026-10-20): child elements, allow-plaintext as %i.
  let(:fresh) do
    xml_doc(<<~XML)
      <describe_auth_response status="200" status_text="OK">
        <group name="method:file">#{setting('enable', 'true')}#{setting('order', '1')}</group>
        <group name="method:ldap_connect">
          #{setting('enable', 'false')}#{setting('order', '0')}
          #{setting('ldaphost', '127.0.0.1')}#{setting('authdn', 'userid=%s,dc=example,dc=org')}
          #{setting('allow-plaintext', '0')}#{setting('ldaps-only', 'false')}
        </group>
      </describe_auth_response>
    XML
  end
  let(:configured) do
    xml_doc(<<~XML)
      <describe_auth_response status="200" status_text="OK">
        <group name="method:ldap_connect">
          #{setting('enable', 'true')}#{setting('order', '0')}
          #{setting('ldaphost', 'ldap.example.org')}#{setting('authdn', 'uid=%s,ou=People,dc=example,dc=org')}
          #{setting('allow-plaintext', '1')}#{setting('ldaps-only', 'true')}
          <auth_conf_setting><key>cacert</key><value>-----BEGIN CERTIFICATE-----
      MIIB
      -----END CERTIFICATE-----
      </value><certificate_info><time_status>valid</time_status></certificate_info></auth_conf_setting>
        </group>
      </describe_auth_response>
    XML
  end

  def xml_doc(str)
    REXML::Document.new(str)
  end

  def setting(key, value)
    "<auth_conf_setting><key>#{key}</key><value>#{value}</value></auth_conf_setting>"
  end

  describe '#get' do
    it 'returns an empty array when transport_command returns nil' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns an empty array when the ldap_connect group is absent (gvmd built without LDAP)' do
      allow(provider).to receive(:transport_command).and_return(xml_doc('<describe_auth_response status="200"/>'))
      expect(provider.get(context)).to eq([])
    end

    it 'reads the child-element format gvmd really sends' do
      allow(provider).to receive(:transport_command).and_return(fresh)
      expect(provider.get(context)).to eq([{
                                            ensure: 'absent', name: 'ldap_connect',
                                            ldaphost: '127.0.0.1', authdn: 'userid=%s,dc=example,dc=org',
                                            cacert: nil, allow_plaintext: false, ldaps_only: false,
                                          }])
    end

    it 'reads a configured group, allow-plaintext as 1 and the cacert without certificate_info' do
      allow(provider).to receive(:transport_command).and_return(configured)
      r = provider.get(context).first
      expect(r).to include(ensure: 'present', ldaphost: 'ldap.example.org',
                           authdn: 'uid=%s,ou=People,dc=example,dc=org',
                           allow_plaintext: true, ldaps_only: true)
      expect(r[:cacert]).to eq("-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----")
    end
  end

  describe '#canonicalize' do
    it 'compares PEMs ignoring CRLF and surrounding whitespace' do
      r = provider.canonicalize(context, [{ name: 'ldap_connect', cacert: "\r\nA\r\nB\r\n\n" }]).first
      expect(r[:cacert]).to eq("A\nB")
    end
  end

  describe '#create / #update' do
    let(:should_hash) do
      { ldaphost: 'ldap.example.org', authdn: 'uid=%s,dc=example,dc=org', allow_plaintext: false, ldaps_only: true }
    end

    it 'writes key and value as child elements, never attributes' do
      sent = []
      allow(provider).to receive(:transport_command) { |_ctx, xml| sent << xml }
      provider.create(context, 'ldap_connect', should_hash)

      expect(sent.length).to eq(1)
      expect(sent[0]).to start_with('<modify_auth><group name="method:ldap_connect">')
      expect(sent[0]).to include(setting('enable', 'true'), setting('ldaphost', 'ldap.example.org'),
                                 setting('authdn', 'uid=%s,dc=example,dc=org'),
                                 setting('allow-plaintext', 'false'), setting('ldaps-only', 'true'))
      expect(sent[0]).not_to include('key=')
    end

    it 'sends the cacert alone and first, so a bad certificate cannot leave LDAP half switched on' do
      sent = []
      allow(provider).to receive(:transport_command) { |_ctx, xml| sent << xml }
      provider.update(context, 'ldap_connect', should_hash.merge(cacert: 'PEM<&>'))

      expect(sent.length).to eq(2)
      expect(sent[0]).to eq('<modify_auth><group name="method:ldap_connect">' \
                            "#{setting('cacert', 'PEM&lt;&amp;&gt;')}</group></modify_auth>")
      expect(sent[1]).to include(setting('enable', 'true'))
      expect(sent[1]).not_to include('cacert')
    end

    it 'stops before enabling when the cacert is rejected' do
      calls = 0
      allow(provider).to receive(:transport_command) do
        calls += 1
        raise Puppet::ResourceError, 'GMP error 400: Invalid certificate'
      end
      expect { provider.create(context, 'ldap_connect', should_hash.merge(cacert: 'junk')) }
        .to raise_error(Puppet::ResourceError, %r{Invalid certificate})
      expect(calls).to eq(1)
    end

    it 'raises when enabling without ldaphost' do
      expect {
        provider.create(context, 'ldap_connect', authdn: 'uid=%s,dc=example,dc=org', allow_plaintext: false)
      }.to raise_error(Puppet::ResourceError, %r{requires ldaphost})
    end

    it 'raises when enabling without authdn' do
      expect {
        provider.create(context, 'ldap_connect', ldaphost: 'x', allow_plaintext: false)
      }.to raise_error(Puppet::ResourceError, %r{requires authdn})
    end
  end

  describe '#delete' do
    it 'only switches enable off and keeps the stored connection' do
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_auth><group name=\"method:ldap_connect\">#{setting('enable', 'false')}</group></modify_auth>")
      provider.delete(context, 'ldap_connect')
    end
  end
end
