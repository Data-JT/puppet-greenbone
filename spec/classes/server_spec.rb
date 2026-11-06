# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::server' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:hiera_config) { 'spec/fixtures/hiera/hiera.yaml' }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_class('greenbone') }
      it { is_expected.to contain_class('greenbone::database') }
      it { is_expected.to contain_class('greenbone::admin') }

      it 'orders the stack: database before redis' do
        is_expected.to contain_class('greenbone::database').that_comes_before('Class[greenbone::redis]')
      end

      it 'orders the stack: service before admin' do
        is_expected.to contain_class('greenbone::service').that_comes_before('Class[greenbone::admin]')
      end

      it 'orders the stack: admin before feed' do
        is_expected.to contain_class('greenbone::admin').that_comes_before('Class[greenbone::feed]')
      end

      it 'does not manage LDAP by default' do
        is_expected.not_to contain_class('greenbone::ldap')
      end

      context 'with manage_ldap => true' do
        let(:params) { { manage_ldap: true } }
        let(:hiera_config) { 'spec/fixtures/hiera/hiera.yaml' }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('greenbone::ldap') }

        it 'orders ldap between admin and feed' do
          is_expected.to contain_class('greenbone::admin').that_comes_before('Class[greenbone::ldap]')
          is_expected.to contain_class('greenbone::ldap').that_comes_before('Class[greenbone::feed]')
        end
      end
    end
  end
end
