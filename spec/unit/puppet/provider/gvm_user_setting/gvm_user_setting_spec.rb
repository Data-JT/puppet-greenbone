# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_user_setting/gvm_user_setting'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmUserSetting::GvmUserSetting do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }

  def xml_doc(str)
    REXML::Document.new(str)
  end

  describe '#get' do
    it 'returns an empty array when transport_command returns nil' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'parses settings and caches their ids' do
      doc = xml_doc(<<~XML)
        <get_settings_response status="200">
          <setting id="11111111-1111-1111-1111-111111111111">
            <name>Rows Per Page</name>
            <value>10</value>
          </setting>
          <setting id="22222222-2222-2222-2222-222222222222">
            <name>Timezone</name>
            <value>UTC</value>
          </setting>
        </get_settings_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      result = provider.get(context)
      expect(result.map { |r| r[:name] }).to contain_exactly('Rows Per Page', 'Timezone')
      expect(result.find { |r| r[:name] == 'Rows Per Page' }[:value]).to eq('10')
      expect(provider.instance_variable_get(:@setting_ids)).to include(
        'Rows Per Page' => '11111111-1111-1111-1111-111111111111',
        'Timezone' => '22222222-2222-2222-2222-222222222222',
      )
    end

    it 'ignores settings whose id is not a valid UUID' do
      doc = xml_doc(<<~XML)
        <get_settings_response status="200">
          <setting id="not-a-uuid">
            <name>Bad Setting</name>
            <value>x</value>
          </setting>
        </get_settings_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      provider.get(context)
      expect(provider.instance_variable_get(:@setting_ids)).not_to have_key('Bad Setting')
    end
  end

  describe '#update' do
    before(:each) do
      provider.instance_variable_set(:@setting_ids, {
                                       'Rows Per Page' => '11111111-1111-1111-1111-111111111111',
                                     })
    end

    it 'sends modify_setting XML with the cached id' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('11111111-1111-1111-1111-111111111111')
        expect(xml).to include('<value>MjA=</value>')
      end
      provider.update(context, 'Rows Per Page', { value: '20' })
    end

    it 'falls back to a fresh GMP lookup when the id is not cached' do
      # Simulate set running without a prior get (no cache).
      provider.instance_variable_set(:@setting_ids, nil)
      lookup = xml_doc(<<~XML)
        <get_settings_response status="200">
          <setting id="33333333-3333-3333-3333-333333333333">
            <name>Fresh Setting</name>
            <value>old</value>
          </setting>
        </get_settings_response>
      XML
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        (xml == '<get_settings/>') ? lookup : nil
      end

      provider.update(context, 'Fresh Setting', { value: 'new' })

      expect(sent).to include('<get_settings/>')
      modify = sent.find { |x| x.include?('modify_setting') }
      expect(modify).to include('33333333-3333-3333-3333-333333333333', '<value>bmV3</value>')
    end

    it 'raises when the setting exists in neither the cache nor a fresh lookup' do
      empty = xml_doc('<get_settings_response status="200"/>')
      allow(provider).to receive(:transport_command).and_return(empty)
      expect {
        provider.update(context, 'Unknown Setting', { value: 'x' })
      }.to raise_error(Puppet::ResourceError, %r{GVM setting not found})
    end
  end

  describe 'base64 values' do
    # gvmd rejects a plain <value> with "Value cannot be decoded to valid
    # UTF-8" (measured 2026-10-20); the type never worked before this.
    before(:each) do
      provider.instance_variable_set(:@setting_ids, { 'Timezone' => '11111111-1111-1111-1111-111111111111' })
    end

    it 'encodes strictly, without line breaks, even for a long value' do
      long = 'x' * 200
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include("<value>#{[long].pack('m0')}</value>")
        expect(xml).not_to include("\n")
      end
      provider.update(context, 'Timezone', { value: long })
    end

    it 'encodes an empty value as an empty element' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<value></value>')
      end
      provider.update(context, 'Timezone', { value: '' })
    end
  end

  describe 'setting_id' do
    let(:sid) { '739ab810-163d-11e3-9af6-406186ea4fc5' }

    it 'is used directly for a setting gvmd does not list yet' do
      sent = []
      allow(provider).to receive(:transport_command) { |_ctx, xml|
        sent << xml
        nil
      }
      provider.update(context, 'Results Filter', { value: 'v', setting_id: sid })
      expect(sent).to eq(["<modify_setting setting_id=\"#{sid}\"><value>dg==</value></modify_setting>"])
    end
  end

  describe 'filter_name' do
    let(:sid) { '739ab810-163d-11e3-9af6-406186ea4fc5' }
    let(:fid) { 'cb1ef0f5-b97a-4518-9914-bc0042850c61' }

    it 'writes the UUID of the named filter' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'filter', 'Mine').and_return(fid)
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include("<value>#{[fid].pack('m0')}</value>")
      end
      provider.update(context, 'Results Filter', { filter_name: 'Mine', setting_id: sid })
    end

    it 'raises when the filter does not exist' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect {
        provider.update(context, 'Results Filter', { filter_name: 'Gone', setting_id: sid })
      }.to raise_error(Puppet::ResourceError, %r{filter not found: Gone})
    end

    it 'refuses value and filter_name together, and neither' do
      expect {
        provider.update(context, 'Results Filter', { value: 'x', filter_name: 'Mine', setting_id: sid })
      }.to raise_error(Puppet::ResourceError, %r{exactly one})
      expect {
        provider.update(context, 'Results Filter', { setting_id: sid })
      }.to raise_error(Puppet::ResourceError, %r{exactly one})
    end

    it 'is read back as the filter name, so the manifest compares by name' do
      settings = xml_doc(<<~XML)
        <get_settings_response status="200">
          <setting id="#{sid}"><name>Results Filter</name><value>#{fid}</value></setting>
          <setting id="11111111-1111-1111-1111-111111111111"><name>Rows Per Page</name><value>10</value></setting>
        </get_settings_response>
      XML
      filters = xml_doc(<<~XML)
        <get_filters_response status="200">
          <filter id="#{fid}"><name>Mine</name></filter>
        </get_filters_response>
      XML
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        xml.start_with?('<get_settings') ? settings : filters
      end

      result = provider.get(context)
      expect(result.find { |r| r[:name] == 'Results Filter' }).to include(value: fid, filter_name: 'Mine')
      expect(result.find { |r| r[:name] == 'Rows Per Page' }[:filter_name]).to be_nil
    end

    it 'does not query filters when no setting holds a UUID' do
      settings = xml_doc('<get_settings_response status="200"><setting id="11111111-1111-1111-1111-111111111111"><name>Rows Per Page</name><value>10</value></setting></get_settings_response>')
      expect(provider).to receive(:transport_command).once.and_return(settings)
      provider.get(context)
    end
  end

  describe '#delete' do
    it 'always raises because GVM settings cannot be deleted' do
      expect {
        provider.delete(context, 'Any Setting')
      }.to raise_error(Puppet::ResourceError, %r{cannot be deleted})
    end
  end

  describe '#create' do
    it 'delegates to update' do
      expect(provider).to receive(:update).with(context, 'Rows Per Page', { value: '5' })
      provider.create(context, 'Rows Per Page', { value: '5' })
    end
  end
end
