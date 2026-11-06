# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::config' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) { "class { 'greenbone': password => Sensitive('x'), repo_key_id => '0123456789ABCDEF0123456789ABCDEF01234567' }" }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_file('/etc/openvas/openvas.conf').with_mode('0640') }
      it { is_expected.to contain_file('/etc/gvm/gvmd.conf').with_mode('0640') }

      it 'writes the redis socket into openvas.conf' do
        is_expected.to contain_file('/etc/openvas/openvas.conf').with_content(%r{db_address})
      end

      { redis_socket: 'redis.sock', scanner_socket: 'ospd.sock', gvmd_socket: 'gvmd.sock' }.each do |param, value|
        context "with an invalid #{param}" do
          let(:params) { { param => value } }

          it { is_expected.to compile.and_raise_error(%r{#{param}}) }
        end
      end
    end
  end
end
