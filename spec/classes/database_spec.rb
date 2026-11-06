# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::database' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:hiera_config) { 'spec/fixtures/hiera/hiera.yaml' }
      let(:pre_condition) { "class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }" }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_postgresql__server__db('gvmd') }
      it { is_expected.to contain_postgresql__server__role('gvm') }
      it { is_expected.to contain_postgresql__server__role('dba').with_superuser(true) }
      it { is_expected.to contain_postgresql__server__extension('pg-gvm') }

      it { is_expected.to contain_file('/usr/local/sbin/gvm-migrate').with_mode('0700') }

      it { is_expected.to contain_exec('gvmd-migrate') }

      # When the gvmd package is managed (default via greenbone), the migration
      # exec must be refreshonly and triggered by the package rather than run
      # on every catalog application.
      it 'runs the migration only on package change' do
        is_expected.to contain_exec('gvmd-migrate').with(
          refreshonly: true,
          command: '/usr/local/sbin/gvm-migrate',
        )
      end

      it { is_expected.to contain_exec('gvmd-migrate').that_subscribes_to('Package[gvmd]') }
      it { is_expected.to contain_exec('gvmd-migrate').that_requires('File[/usr/local/sbin/gvm-migrate]') }
    end
  end
end
