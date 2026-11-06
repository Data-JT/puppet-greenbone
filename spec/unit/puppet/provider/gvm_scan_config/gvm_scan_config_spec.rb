# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_scan_config/gvm_scan_config'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmScanConfig::GvmScanConfig do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  let(:cgi_pref) do
    { 'oid' => CGI_OID, 'id' => '18', 'type' => 'checkbox', 'name' => CGI_NAME, 'value' => 'yes' }
  end
  let(:desired) do
    {
      name:                'Full and fast (custom)',
      ensure:              'present',
      base_config:         'Full and fast',
      scanner_preferences: { 'expand_vhosts' => '0' },
      nvt_preferences:     [cgi_pref],
    }
  end

  BASE_ID  = 'daba56c8-73ec-11df-a475-002264764cea'
  CLONE_ID = '4330c49d-7f9f-407d-ab46-bc80238d9b5c'
  NEW_ID   = '11111111-2222-3333-4444-555555555555'
  CGI_OID  = '1.3.6.1.4.1.25623.1.0.12288'
  CGI_NAME = 'Disable caching of web pages during CGI scanning'

  # A small in-memory gvmd: configs by id, each with scanner prefs and NVT
  # prefs keyed by [oid, name]. Writes decode base64 and only land when the
  # NVT preference is addressed by its qualified name -- the two ways a real
  # gvmd silently drops a write -- so the read-back check is exercised.
  class FakeGvmd
    attr_reader :configs, :writes

    def initialize(configs)
      @configs = configs
      @writes  = []
    end

    def call(xml)
      case xml
      when '<get_configs filter="rows=-1"/>'
        rows = configs.map { |id, c| "<config id=\"#{id}\"><name>#{c[:name]}</name></config>" }.join
        doc("<get_configs_response status=\"200\">#{rows}</get_configs_response>")
      when %r{\A<get_configs config_id="([^"]+)" preferences="1"/>\z}
        prefs(Regexp.last_match(1))
      when %r{\A<create_config><copy>([^<]+)</copy><name>([^<]+)</name></create_config>\z}
        base = configs.fetch(Regexp.last_match(1))
        configs[NEW_ID] = { name: Regexp.last_match(2), scanner: base[:scanner].dup, nvt: base[:nvt].dup }
        doc("<create_config_response status=\"201\" id=\"#{NEW_ID}\"/>")
      when %r{\A<modify_config config_id="([^"]+)">(.*)</modify_config>\z}m
        writes << xml
        modify(configs.fetch(Regexp.last_match(1)), REXML::Document.new(Regexp.last_match(2)).root)
        doc('<modify_config_response status="200"/>')
      else
        raise "unexpected GMP command: #{xml}"
      end
    end

    private

    def modify(config, pref)
      name  = REXML::XPath.first(pref, 'name').text
      value = REXML::XPath.first(pref, 'value').text.to_s.unpack1('m0')
      oid   = REXML::XPath.first(pref, 'nvt')&.attributes&.[]('oid')
      if oid
        parts = name.split(':', 4)
        return unless parts.size == 4 && parts[0] == oid # plain name: 200, nothing stored

        key = [oid, parts[3]]
        config[:nvt][key] = config[:nvt][key].merge(value: value)
      else
        config[:scanner][name] = value
      end
    end

    def prefs(id)
      c = configs[id]
      return doc('<get_configs_response status="200"/>') unless c

      scanner = c[:scanner].map do |n, v|
        "<preference><nvt oid=\"\"><name/></nvt><id/><name>#{n}</name><type/><value>#{v}</value></preference>"
      end
      nvt = c[:nvt].map do |(oid, n), p|
        "<preference><nvt oid=\"#{oid}\"><name>Global variable settings</name></nvt><id>#{p[:id]}</id>" \
          "<name>#{n}</name><type>#{p[:type]}</type><value>#{p[:value]}</value></preference>"
      end
      doc("<get_configs_response status=\"200\"><config id=\"#{id}\"><name>#{c[:name]}</name>" \
          "<preferences>#{(scanner + nvt).join}</preferences></config></get_configs_response>")
    end

    def doc(str)
      REXML::Document.new(str)
    end
  end

  def feed_config(name, expand: '1', cgi: 'no')
    {
      name:    name,
      scanner: { 'expand_vhosts' => expand, 'alive_test_ports' => '21-23,80' },
      nvt:     { [CGI_OID, CGI_NAME] => { id: '18', type: 'checkbox', value: cgi } },
    }
  end

  def wire(gvmd)
    allow(provider).to receive(:transport_command) { |_ctx, xml| gvmd.call(xml) }
  end

  describe '#get' do
    it 'returns an empty array when the transport is not configured' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'separates scanner from NVT preferences by the oid ATTRIBUTE' do
      wire(FakeGvmd.new(CLONE_ID => feed_config('Full and fast (custom)', expand: '0', cgi: 'yes')))

      result = provider.get(context, ['Full and fast (custom)'])
      expect(result.size).to eq(1)
      expect(result[0][:scanner_preferences]).to eq('expand_vhosts' => '0', 'alive_test_ports' => '21-23,80')
      expect(result[0][:nvt_preferences]).to eq([{ 'oid' => CGI_OID, 'id' => '18', 'type' => 'checkbox', 'name' => CGI_NAME, 'value' => 'yes' }])
    end

    it 'reads only the named configs when given names' do
      gvmd = FakeGvmd.new(BASE_ID => feed_config('Full and fast'), CLONE_ID => feed_config('Full and fast (custom)'))
      wire(gvmd)
      expect(provider.get(context, ['Full and fast (custom)']).map { |r| r[:name] }).to eq(['Full and fast (custom)'])
    end
  end

  describe '#insync?' do
    let(:is_hash) do
      {
        scanner_preferences: { 'expand_vhosts' => '0', 'alive_test_ports' => '21-23,80' },
        nvt_preferences:     [{ 'oid' => CGI_OID, 'id' => '18', 'type' => 'checkbox', 'name' => CGI_NAME, 'value' => 'yes' },
                              { 'oid' => CGI_OID, 'id' => '19', 'type' => 'entry', 'name' => 'Traversal depth', 'value' => '6' }],
      }
    end

    it 'ignores preferences the manifest does not list' do
      expect(provider.insync?(context, 'x', :scanner_preferences, is_hash, desired)).to eq([true, nil])
      expect(provider.insync?(context, 'x', :nvt_preferences, is_hash, desired)).to eq([true, nil])
    end

    it 'reports a listed preference that drifted' do
      is_hash[:scanner_preferences]['expand_vhosts'] = '1'
      ok, message = provider.insync?(context, 'x', :scanner_preferences, is_hash, desired)
      expect(ok).to be(false)
      expect(message).to include('expand_vhosts', '"1" -> "0"')
    end

    it 'treats a missing NVT preference as drift' do
      is_hash[:nvt_preferences] = []
      expect(provider.insync?(context, 'x', :nvt_preferences, is_hash, desired).first).to be(false)
    end

    it 'leaves other properties to the default comparison' do
      expect(provider.insync?(context, 'x', :ensure, is_hash, desired)).to be_nil
    end
  end

  describe '#create' do
    it 'clones the base and writes the drifted preferences under their qualified names' do
      gvmd = FakeGvmd.new(BASE_ID => feed_config('Full and fast'))
      wire(gvmd)

      provider.create(context, 'Full and fast (custom)', desired)

      clone = gvmd.configs.fetch(NEW_ID)
      expect(clone[:name]).to eq('Full and fast (custom)')
      expect(clone[:scanner]['expand_vhosts']).to eq('0')
      expect(clone[:nvt][[CGI_OID, CGI_NAME]][:value]).to eq('yes')
      expect(gvmd.writes).to include(include("<name>#{CGI_OID}:18:checkbox:#{CGI_NAME}</name>"))
      expect(gvmd.configs.fetch(BASE_ID)[:scanner]['expand_vhosts']).to eq('1')
    end

    it 'fails when the base config does not exist' do
      wire(FakeGvmd.new({}))
      expect { provider.create(context, 'X', desired) }.to raise_error(Puppet::ResourceError, %r{feed may not be synced})
    end
  end

  describe '#update' do
    it 'writes nothing when the listed preferences already match' do
      gvmd = FakeGvmd.new(CLONE_ID => feed_config('Full and fast (custom)', expand: '0', cgi: 'yes'))
      wire(gvmd)
      provider.update(context, 'Full and fast (custom)', desired)
      expect(gvmd.writes).to be_empty
    end

    it 'restores a preference changed in the web UI' do
      gvmd = FakeGvmd.new(CLONE_ID => feed_config('Full and fast (custom)', expand: '1', cgi: 'yes'))
      wire(gvmd)
      provider.update(context, 'Full and fast (custom)', desired)
      expect(gvmd.writes.size).to eq(1)
      expect(gvmd.configs.fetch(CLONE_ID)[:scanner]['expand_vhosts']).to eq('0')
    end

    it 'fails when a write does not read back, instead of reporting success' do
      gvmd = FakeGvmd.new(CLONE_ID => feed_config('Full and fast (custom)', expand: '0', cgi: 'no'))
      wire(gvmd)
      # The id does not match the feed's, so the qualified name is wrong for
      # this OID's preference and the fake drops the write, as gvmd does.
      bad = desired.merge(nvt_preferences: [cgi_pref.merge('id' => '99')])
      allow(gvmd).to receive(:call).and_wrap_original do |orig, xml|
        orig.call(xml.sub("#{CGI_OID}:99", 'wrong-oid:99'))
      end
      expect { provider.update(context, 'Full and fast (custom)', bad) }
        .to raise_error(Puppet::ResourceError, %r{did not store it})
    end

    it 'refuses to pick between two configs of the same name' do
      wire(FakeGvmd.new(CLONE_ID => feed_config('Dup'), NEW_ID => feed_config('Dup')))
      expect { provider.update(context, 'Dup', desired) }.to raise_error(Puppet::ResourceError, %r{refusing to guess})
    end
  end

  describe '#delete' do
    it 'deletes the config by id' do
      allow(provider).to receive(:config_id).with(context, 'Full and fast (custom)').and_return(CLONE_ID)
      expect(provider).to receive(:transport_command).with(context, "<delete_config config_id=\"#{CLONE_ID}\" ultimate=\"1\"/>")
      provider.delete(context, 'Full and fast (custom)')
    end
  end
end
