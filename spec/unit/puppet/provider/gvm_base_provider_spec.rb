# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_base_provider'
require 'puppet/transport/greenbone'

RSpec.describe Puppet::Provider::GvmBaseProvider do
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', debug: nil) }
  let(:config_path) { described_class.config_path }
  let(:valid_config) do
    { 'user' => 'admin', 'password' => 'secret', 'socket' => '/run/gvmd/sock' }
  end

  before(:each) do
    allow(Puppet::Transport::Greenbone).to receive(:new).and_return(instance_double(Puppet::Transport::Greenbone))
  end

  # ─── build_transport: YAML validation ────────────────────────────────────────

  describe '.build_transport' do
    context 'with a valid YAML mapping' do
      before(:each) { allow(YAML).to receive(:safe_load_file).with(config_path).and_return(valid_config) }

      it 'constructs a Greenbone transport' do
        expect(Puppet::Transport::Greenbone).to receive(:new)
          .with(context, { user: 'admin', password: 'secret', socket: '/run/gvmd/sock' })
        described_class.build_transport(context)
      end
    end

    context 'when the YAML is not a mapping' do
      [nil, 'just a string', [1, 2, 3], 42].each do |bad|
        it "raises for #{bad.inspect}" do
          allow(YAML).to receive(:safe_load_file).and_return(bad)
          expect { described_class.build_transport(context) }
            .to raise_error(Puppet::ResourceError, %r{must be a YAML mapping})
        end
      end
    end

    context 'when a required key is missing' do
      ['user', 'password', 'socket'].each do |key|
        it "raises when '#{key}' is absent" do
          allow(YAML).to receive(:safe_load_file).and_return(valid_config.reject { |k, _| k == key })
          expect { described_class.build_transport(context) }
            .to raise_error(Puppet::ResourceError, %r{key '#{key}' must be a non-empty string})
        end
      end
    end

    context 'when a required key is an empty string' do
      it 'raises' do
        allow(YAML).to receive(:safe_load_file).and_return(valid_config.merge('user' => ''))
        expect { described_class.build_transport(context) }
          .to raise_error(Puppet::ResourceError, %r{key 'user' must be a non-empty string})
      end
    end

    context 'when a required key is the wrong type' do
      it 'raises when password is an integer' do
        allow(YAML).to receive(:safe_load_file).and_return(valid_config.merge('password' => 42))
        expect { described_class.build_transport(context) }
          .to raise_error(Puppet::ResourceError, %r{key 'password' must be a non-empty string})
      end
    end

    context 'when the config file does not exist' do
      it 'raises with a helpful message' do
        allow(YAML).to receive(:safe_load_file).and_raise(Errno::ENOENT)
        expect { described_class.build_transport(context) }
          .to raise_error(Puppet::ResourceError, %r{transport config not found})
      end
    end
  end

  # ─── gmp_escape_filter: XPath and GMP filter injection ───────────────────────

  describe '#gmp_escape_filter (private)' do
    # A minimal provider instance: allocate bypasses the superclass
    # constructor, which requires a Resource API context.
    subject(:provider) do
      described_class.allocate
    end

    it 'wraps the value in &quot; delimiters' do
      expect(provider.send(:gmp_escape_filter, 'admin')).to eq('&quot;admin&quot;')
    end

    it 'strips embedded double quotes to prevent GMP filter injection' do
      expect(provider.send(:gmp_escape_filter, 'a"b')).to eq('&quot;ab&quot;')
    end

    it 'handles the empty string safely' do
      expect(provider.send(:gmp_escape_filter, '')).to eq('&quot;&quot;')
    end

    it 'does not alter XPath wildcards (they are safe inside a quoted filter)' do
      expect(provider.send(:gmp_escape_filter, 'task*')).to eq('&quot;task*&quot;')
    end

    it 'handles names with single quotes (no escaping needed inside &quot; delimiters)' do
      expect(provider.send(:gmp_escape_filter, "it's")).to eq("&quot;it's&quot;")
    end
  end

  # ─── transport lifecycle ─────────────────────────────────────────────────────

  describe 'transport handling' do
    subject(:provider) do
      Class.new(described_class) {
        def get(_context)
          [{ name: 'existing', ensure: 'present' }]
        end
      }.allocate
    end

    let(:transport) { instance_double(Puppet::Transport::Greenbone) }
    let(:stat) { instance_double(File::Stat, mtime: Time.at(1), size: 10) }

    before(:each) do
      allow(described_class).to receive(:build_transport).and_return(transport)
      allow(File).to receive(:stat).with(config_path).and_return(stat)
    end

    it 'builds the transport once while the config file is unchanged' do
      expect(described_class).to receive(:build_transport).once.and_return(transport)
      2.times { expect(provider.gvm_transport(context)).to be(transport) }
    end

    it 'rebuilds the transport when the config file changes' do
      provider.gvm_transport(context)
      allow(File).to receive(:stat).with(config_path).and_return(instance_double(File::Stat, mtime: Time.at(2), size: 10))
      expect(described_class).to receive(:build_transport).and_return(instance_double(Puppet::Transport::Greenbone))
      provider.gvm_transport(context)
    end

    it 'sends commands through the transport' do
      allow(transport).to receive(:command).with(context, '<get_x/>').and_return(:doc)
      expect(provider.transport_command(context, '<get_x/>')).to eq(:doc)
    end

    it 'answers nil when the transport config is missing, so discovery finds nothing' do
      allow(described_class).to receive(:build_transport)
        .and_raise(Puppet::ResourceError, "Greenbone transport config not found at #{config_path}; x")
      expect(provider.transport_command(context, '<get_x/>')).to be_nil
    end

    it 're-raises every other transport error' do
      allow(transport).to receive(:command).and_raise(Puppet::ResourceError, 'GMP error 400: nope')
      expect { provider.transport_command(context, '<get_x/>') }.to raise_error(Puppet::ResourceError, %r{nope})
    end

    # The transport file is created by the same run that manages the gvm_*
    # resources. Their is-state was read before it existed, so set() re-reads
    # it rather than creating objects that exist.
    describe '#set after a missing transport config' do
      let(:type) { instance_double(Puppet::ResourceApi::TypeDefinition, namevars: [:name], feature?: false, ensurable?: true) }
      let(:set_context) do
        instance_double('Puppet::ResourceApi::BaseContext', debug: nil, type: type).tap do |ctx|
          allow(ctx).to receive(:creating).and_yield
          allow(ctx).to receive(:updating).and_yield
        end
      end

      before(:each) do
        allow(described_class).to receive(:build_transport)
          .and_raise(Puppet::ResourceError, "Greenbone transport config not found at #{config_path}; x")
        provider.transport_command(set_context, '<get_x/>')
      end

      it 'updates an object that turns out to exist' do
        should = { name: 'existing', ensure: 'present' }
        expect(provider).to receive(:update).with(set_context, 'existing', should)
        expect(provider).not_to receive(:create)
        provider.set(set_context, 'existing' => { is: { name: 'existing', ensure: 'absent' }, should: should })
      end

      it 'creates an object that is still absent' do
        should = { name: 'new', ensure: 'present' }
        expect(provider).to receive(:create).with(set_context, 'new', should)
        provider.set(set_context, 'new' => { is: { name: 'new', ensure: 'absent' }, should: should })
      end
    end
  end

  # ─── resolve_name_to_id ──────────────────────────────────────────────────────

  describe '#resolve_name_to_id' do
    subject(:provider) do
      described_class.allocate
    end

    let(:uuid) { '01234567-89ab-cdef-0123-456789abcdef' }

    def response(xml)
      REXML::Document.new(xml)
    end

    it 'filters by the quoted name and returns the exact match' do
      doc = response(<<~XML)
        <get_targets_response status="200">
          <target id="11111111-1111-1111-1111-111111111111"><name>web servers</name></target>
          <target id="#{uuid}"><name>web</name></target>
        </get_targets_response>
      XML
      expect(provider).to receive(:transport_command)
        .with(context, '<get_targets filter="name=&quot;web&quot;"/>').and_return(doc)
      expect(provider.resolve_name_to_id(context, 'target', 'web')).to eq(uuid)
    end

    it 'returns nil when no object has that exact name' do
      allow(provider).to receive(:transport_command)
        .and_return(response('<get_targets_response status="200"><target id="x"><name>webx</name></target></get_targets_response>'))
      expect(provider.resolve_name_to_id(context, 'target', 'web')).to be_nil
    end

    it 'returns nil when the transport is not configured' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.resolve_name_to_id(context, 'target', 'web')).to be_nil
    end

    it 'refuses an id that is not a UUID, since it is interpolated into XML' do
      allow(provider).to receive(:transport_command)
        .and_return(response('<get_targets_response status="200"><target id="x&quot;/&gt;"><name>web</name></target></get_targets_response>'))
      expect { provider.resolve_name_to_id(context, 'target', 'web') }.to raise_error(Puppet::ResourceError, %r{invalid UUID})
    end
  end

  # ─── xe ──────────────────────────────────────────────────────────────────────

  describe '#xe' do
    subject(:provider) do
      described_class.allocate
    end

    it 'escapes the characters that would break out of element content' do
      expect(provider.xe('a<b>&c')).to eq('a&lt;b&gt;&amp;c')
    end

    it 'turns nil into an empty string' do
      expect(provider.xe(nil)).to eq('')
    end
  end

  # ─── delete_properties ───────────────────────────────────────────────────────

  describe '#insync?' do
    subject(:provider) do
      described_class.allocate
    end

    it 'leaves every other attribute to the Resource API default' do
      expect(provider.insync?(context, 'x', :comment, { comment: 'a' }, { comment: 'b' })).to be_nil
    end

    it 'is out of sync while a listed property is still set' do
      should = { delete_properties: ['comment'] }
      expect(provider.insync?(context, 'x', :delete_properties, { comment: 'old' }, should)).to be(false)
    end

    it 'is in sync once every listed property reads back unset' do
      should = { delete_properties: ['comment', 'exclude_hosts'] }
      expect(provider.insync?(context, 'x', :delete_properties, { comment: nil }, should)).to be(true)
    end

    it 'refuses to set and delete the same property, which could never converge' do
      should = { comment: 'new', delete_properties: ['comment'] }
      expect { provider.insync?(context, 'x', :delete_properties, { comment: 'old' }, should) }
        .to raise_error(Puppet::ResourceError, %r{set and delete the same properties: comment})
    end

    it 'reports whether should asks to clear an attribute' do
      expect(provider.deleting?({ delete_properties: ['comment'] }, :comment)).to be(true)
      expect(provider.deleting?({}, :comment)).to be(false)
    end
  end
end
