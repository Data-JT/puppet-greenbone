# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::feed' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) do
        <<~PP
          class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }
          include greenbone::service
        PP
      end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_file('/etc/systemd/system/greenbone-feed-sync.service') }
      it { is_expected.to contain_file('/etc/systemd/system/greenbone-feed-sync.timer') }
      it { is_expected.to contain_service('greenbone-feed-sync.timer').with_ensure('running') }

      context 'with an invalid sync_args element' do
        let(:params) { { sync_args: ['--foo bar'] } }

        it { is_expected.to compile.and_raise_error(%r{disallowed characters}) }
      end
    end
  end
end
