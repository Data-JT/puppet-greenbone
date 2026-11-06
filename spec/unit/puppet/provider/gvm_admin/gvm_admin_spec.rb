# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_admin'
require 'puppet/provider/gvm_admin/gvm_admin'

RSpec.describe Puppet::Type.type(:gvm_admin).provider(:gvm_admin) do
  let(:resource) do
    Puppet::Type.type(:gvm_admin).new(
      name:     'admin',
      password: 'bootstrap-secret',
      ensure:   :present,
    )
  end

  let(:provider) { described_class.new(resource) }

  describe '#exists?' do
    it 'returns true when the user appears in gvmd --get-users output' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with(['/usr/sbin/gvmd', '--get-users'], anything)
        .and_return("admin\nother\n")
      expect(provider.exists?).to be true
    end

    it 'returns false when the user is not in gvmd --get-users output' do
      allow(Puppet::Util::Execution).to receive(:execute)
        .with(['/usr/sbin/gvmd', '--get-users'], anything)
        .and_return("other\n")
      expect(provider.exists?).to be false
    end

    it 'raises Puppet::Error when gvmd execution fails' do
      allow(Puppet::Util::Execution).to receive(:execute).and_raise(Puppet::ExecutionFailure, 'gvmd crashed')
      expect { provider.exists? }.to raise_error(Puppet::Error, %r{Failed to query GVM users})
    end
  end

  describe '#create' do
    it 'calls gvmd with --create-user and --password using array execution' do
      expect(Puppet::Util::Execution).to receive(:execute) do |cmd, opts|
        expect(cmd).to eq(['/usr/sbin/gvmd', '--create-user=admin', '--password=bootstrap-secret'])
        expect(opts[:sensitive]).to be true
        expect(opts[:failonfail]).to be true
      end
      provider.create
    end

    it 'unwraps a Sensitive password before passing to gvmd' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('wrapped-secret')
      resource[:password] = sensitive
      expect(Puppet::Util::Execution).to receive(:execute) do |cmd, _opts|
        expect(cmd[2]).to eq('--password=wrapped-secret')
      end
      provider.create
    end
  end

  describe '#destroy' do
    it 'calls gvmd with --delete-user' do
      expect(Puppet::Util::Execution).to receive(:execute) do |cmd, opts|
        expect(cmd).to eq(['/usr/sbin/gvmd', '--delete-user=admin'])
        expect(opts[:failonfail]).to be true
      end
      provider.destroy
    end
  end
end
