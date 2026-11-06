# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::ldap' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) do
        <<~PP
          class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }
        PP
      end
      let(:params) do
        {
          ldaphost: 'ldap.example.org',
          authdn:   'uid=%s,ou=people,dc=example,dc=org',
        }
      end

      it { is_expected.to compile.with_all_deps }

      it 'declares the ldap_connect resource as present with mapped params' do
        is_expected.to contain_gvm_ldap('ldap_connect').with(
          ensure: 'present',
          ldaphost: 'ldap.example.org',
          authdn: 'uid=%s,ou=people,dc=example,dc=org',
          allow_plaintext: false,
        )
      end

      context 'with enable => false' do
        let(:params) { super().merge(enable: false) }

        it 'declares the resource as absent' do
          is_expected.to contain_gvm_ldap('ldap_connect').with(ensure: 'absent')
        end
      end
    end
  end
end
