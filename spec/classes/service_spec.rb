# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone::service' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_service('gvmd').with_ensure('running') }
      it { is_expected.to contain_service('gvmd').that_requires('Service[ospd-openvas]') }
      it { is_expected.to contain_service('gsad').that_requires('Service[gvmd]') }

      context 'with a require on a service not in the managed set' do
        let(:params) { { services: { 'gvmd' => { 'require' => ['nonexistent'] } } } }

        it { is_expected.to compile.and_raise_error(%r{not in the managed services set}) }
      end
    end
  end
end
