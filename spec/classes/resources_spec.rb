# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::resources' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) { "class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }" }

      context 'with no data (defaults)' do
        it { is_expected.to compile.with_all_deps }
      end

      context 'with target, schedule and task data' do
        let(:params) do
          {
            schedules: { 'weekly' => { 'icalendar' => 'BEGIN:VCALENDAR', 'timezone' => 'Europe/Berlin' } },
            targets: { 'net' => { 'hosts' => '192.0.2.0/24', 'port_list_name' => 'All IANA assigned TCP' } },
            tasks: { 'scan' => { 'target_name' => 'net', 'config_name' => 'Full and fast', 'schedule_name' => 'weekly' } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_gvm_target('net') }
        it { is_expected.to contain_gvm_schedule('weekly') }
        it { is_expected.to contain_gvm_task('scan') }
        it { is_expected.to contain_gvm_target('net').that_comes_before('Gvm_task[scan]') }
        it { is_expected.to contain_gvm_schedule('weekly').that_comes_before('Gvm_task[scan]') }
      end

      context 'with a scan config a task names' do
        let(:params) do
          {
            targets: { 'net' => { 'hosts' => '192.0.2.0/24', 'port_list_name' => 'All IANA assigned TCP' } },
            scan_configs: { 'Tuned' => { 'base_config' => 'Full and fast', 'scanner_preferences' => { 'expand_vhosts' => '0' } } },
            tasks: { 'scan' => { 'target_name' => 'net', 'config_name' => 'Tuned' } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_gvm_scan_config('Tuned').with_base_config('Full and fast') }
        it { is_expected.to contain_gvm_scan_config('Tuned').that_comes_before('Gvm_task[scan]') }
      end

      context 'with a filter a user setting names' do
        let(:params) do
          {
            filters: { 'Mine' => { 'term' => 'apply_overrides=1 first=1 rows=100 sort=name' } },
            user_settings: { 'Results Filter' => { 'filter_name' => 'Mine', 'setting_id' => '739ab810-163d-11e3-9af6-406186ea4fc5' } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_gvm_filter('Mine').with_term('apply_overrides=1 first=1 rows=100 sort=name') }
        it { is_expected.to contain_gvm_filter('Mine').that_comes_before('Gvm_user_setting[Results Filter]') }
      end

      context 'with a user, a group and a Super permission' do
        let(:params) do
          {
            users: { 'alice' => { 'role_name' => 'Admin', 'source' => 'ldap_connect' } },
            groups: { 'Shared' => { 'users' => ['admin'] } },
            permissions: { 'alice-super' => { 'permission' => 'Super', 'subject_type' => 'user', 'subject_name' => 'alice',
                                              'resource_type' => 'group', 'resource_name' => 'Shared' } },
          }
        end

        it { is_expected.to compile }
        it { is_expected.to contain_gvm_user('alice').that_comes_before('Gvm_group[Shared]') }
        it { is_expected.to contain_gvm_user('alice').that_comes_before('Gvm_permission[alice-super]') }
        it { is_expected.to contain_gvm_group('Shared').that_comes_before('Gvm_permission[alice-super]') }
      end
    end
  end
end
