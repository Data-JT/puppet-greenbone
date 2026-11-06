# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_user/gvm_user'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmUser::GvmUser do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }

  def xml_doc(str)
    REXML::Document.new(str)
  end

  describe '#get' do
    it 'returns an empty array when transport_command returns nil' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'parses a user with role and hosts' do
      doc = xml_doc(<<~XML)
        <get_users_response status="200">
          <user id="u1">
            <name>alice</name>
            <role><name>Admin</name></role>
            <hosts allow="1">192.0.2.0/24</hosts>
          </user>
        </get_users_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.length).to eq(1)
      expect(result[0]).to include(
        ensure: 'present',
        name: 'alice',
        role_name: 'Admin',
        hosts: '192.0.2.0/24',
        hosts_allow: true,
        source: 'file',
      )
    end

    it 'parses an LDAP-sourced user' do
      doc = xml_doc(<<~XML)
        <get_users_response status="200">
          <user id="u3">
            <name>carol</name>
            <role><name>User</name></role>
            <hosts allow="0"></hosts>
            <sources><source>ldap_connect</source></sources>
          </user>
        </get_users_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)
      expect(provider.get(context)[0][:source]).to eq('ldap_connect')
    end

    it 'defaults role_name to "User" when role element is absent' do
      doc = xml_doc(<<~XML)
        <get_users_response status="200">
          <user id="u2">
            <name>bob</name>
            <hosts allow="0"></hosts>
          </user>
        </get_users_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result[0][:role_name]).to eq('User')
      expect(result[0][:hosts_allow]).to be false
    end
  end

  describe '#create' do
    it 'raises when role is not found' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'role', 'Admin').and_return(nil)
      expect {
        provider.create(context, 'alice', { role_name: 'Admin', password: 'secret', hosts: '', hosts_allow: false })
      }.to raise_error(Puppet::ResourceError, %r{GVM role not found})
    end

    it 'unwraps a Sensitive password before embedding in XML' do
      sensitive_pw = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret123')
      allow(provider).to receive(:resolve_name_to_id).with(context, 'role', 'User').and_return('role-uuid')
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<password>secret123</password>')
        expect(xml).not_to include('Sensitive')
      end
      provider.create(context, 'bob', { role_name: 'User', password: sensitive_pw, hosts: '', hosts_allow: false })
    end

    it 'sends create_user XML with name and role id' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'role', 'User').and_return('role-uuid')
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<create_user>', '<name>bob</name>', 'role-uuid')
      end
      provider.create(context, 'bob', { role_name: 'User', password: 'pass', hosts: '', hosts_allow: false })
    end

    it 'sends the LDAP source when source is ldap_connect' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'role', 'User').and_return('role-uuid')
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<sources><source>ldap_connect</source></sources>')
      end
      provider.create(context, 'carol', { role_name: 'User', hosts: '', hosts_allow: false, source: 'ldap_connect' })
    end

    # modify_user would store it as a local hash that works whenever LDAP is off.
    it 'refuses a password on an LDAP user, on create and on update' do
      allow(provider).to receive(:resolve_name_to_id).and_return('11111111-1111-1111-1111-111111111111')
      expect(provider).not_to receive(:transport_command)
      ldap = { role_name: 'User', hosts: '', hosts_allow: false, source: 'ldap_connect', password: 'pw' }
      expect { provider.create(context, 'carol', ldap) }.to raise_error(Puppet::ResourceError, %r{only valid with source => 'file'})
      expect { provider.update(context, 'carol', ldap) }.to raise_error(Puppet::ResourceError, %r{only valid with source => 'file'})
    end

    it 'leaves the password out of modify_user for an LDAP user' do
      allow(provider).to receive(:resolve_name_to_id).and_return('11111111-1111-1111-1111-111111111111')
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).not_to include('<password>')
      end
      provider.update(context, 'carol', { role_name: 'User', hosts: '', hosts_allow: false, source: 'ldap_connect' })
    end

    it 'clears hosts with an empty element when delete_properties lists it' do
      allow(provider).to receive(:resolve_name_to_id).and_return('11111111-1111-1111-1111-111111111111')
      expect(provider).to receive(:transport_command).with(context, include('<hosts allow="1"></hosts>'))
      provider.update(context, 'dave', { role_name: 'User', hosts_allow: true, source: 'file', delete_properties: ['hosts'] })
    end
  end

  describe '#delete' do
    it 'raises when user is not found' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.delete(context, 'alice')
      }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end

    it 'sends delete_user XML with the resolved id' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'user', 'alice').and_return('user-uuid')
      expect(provider).to receive(:transport_command).with(context, include('user-uuid'))
      provider.delete(context, 'alice')
    end
  end
end
