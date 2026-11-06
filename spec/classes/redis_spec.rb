# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::redis' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) { "class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }" }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_package('redis-server') }
      it { is_expected.to contain_service('redis-server@openvas').with_ensure('running') }

      # Regression: the rendered config must set unixsocketgroup so the gvm
      # group can connect to the Redis socket.
      it 'renders unixsocketgroup in redis-openvas.conf' do
        is_expected.to contain_file('/etc/redis/redis-openvas.conf').with_content(%r{unixsocketgroup gvm})
      end

      { socket_path: 'redis.sock', socket_perm: 'rwx', config_file: 'redis-openvas.conf' }.each do |param, value|
        context "with an invalid #{param}" do
          let(:params) { { param => value } }

          it { is_expected.to compile.and_raise_error(%r{#{param}}) }
        end
      end
    end
  end
end
