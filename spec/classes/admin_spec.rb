# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::admin' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:hiera_config) { 'spec/fixtures/hiera/hiera.yaml' }
      let(:pre_condition) do
        <<~PP
          class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }
          include greenbone::database
          include greenbone::service
        PP
      end
      let(:params) { { password: sensitive('admin-secret') } }

      it { is_expected.to compile.with_all_deps }

      it 'declares the admin user with the migrate/service ordering' do
        is_expected.to contain_gvm_admin('admin').with(
          ensure: 'present',
          gvmd_bin: '/usr/sbin/gvmd',
          gvm_user: 'gvm',
          gvm_group: 'gvm',
        )
      end

      it { is_expected.to contain_gvm_admin('admin').that_requires('Exec[gvmd-migrate]') }

      { gvmd_bin: 'gvmd', username: '', gvm_user: 'gvm;id' }.each do |param, value|
        context "with an invalid #{param}" do
          let(:params) { super().merge(param => value) }

          it { is_expected.to compile.and_raise_error(%r{#{param}}) }
        end
      end
      it { is_expected.to contain_gvm_admin('admin').that_requires('Service[gvmd]') }
    end
  end
end
