# frozen_string_literal: true

require 'spec_helper_acceptance'

# Smoke test of the base class without touching the apt repo or installing
# packages, so it runs on any provisioned Debian target. It exercises the
# system user/group, runtime directories, and the transport credentials file.
describe 'greenbone class' do
  let(:manifest) do
    <<~PUPPET
      class { 'greenbone':
        password => Sensitive('acceptance-secret'),
        manage_repo        => false,
        manage_packages    => false,
      }
    PUPPET
  end

  it 'applies idempotently' do
    idempotent_apply(manifest)
  end

  describe file('/etc/puppetlabs/puppet/gvm_transport.yaml') do
    it { is_expected.to be_file }
    it { is_expected.to be_mode 600 }
    it { is_expected.to be_owned_by 'root' }
  end

  describe group('gvm') do
    it { is_expected.to exist }
  end

  describe user('gvm') do
    it { is_expected.to exist }
  end

  describe file('/var/lib/gvm') do
    it { is_expected.to be_directory }
  end
end
