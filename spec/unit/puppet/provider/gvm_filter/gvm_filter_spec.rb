# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_filter/gvm_filter'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmFilter::GvmFilter do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  let(:id) { 'cb1ef0f5-b97a-4518-9914-bc0042850c61' }

  def xml_doc(str)
    REXML::Document.new(str)
  end

  def canon(term)
    provider.canonicalize(context, [{ name: 'f', term: term }]).first[:term]
  end

  describe '#canonicalize' do
    # Each pair is a create_filter round-trip measured against gvmd 26.42 on
    # 2026-10-20. If gvmd changes how it completes a term, these are the cases
    # that will start churning.
    {
      'apply_overrides=1 min_qod=70'                => 'apply_overrides=1 min_qod=70 first=1 rows=10 sort=name',
      'rows=50 apply_overrides=1'                   => 'rows=50 apply_overrides=1 first=1 sort=name',
      'sort-reverse=severity apply_overrides=1'     => 'sort-reverse=severity apply_overrides=1 first=1 rows=10',
      'apply_overrides=1 and min_qod=70'            => 'apply_overrides=1 and min_qod=70 first=1 rows=10 sort=name',
      'name~"x y" apply_overrides=1'                => 'name~"x y" apply_overrides=1 first=1 rows=10 sort=name',
      'apply_overrides=1   levels=chml rows=100 min_qod=70 first=1 sort-reverse=severity' =>
        'apply_overrides=1 levels=chml rows=100 min_qod=70 first=1 sort-reverse=severity',
    }.each do |given, stored|
      it "stores #{given.inspect} the way gvmd does" do
        expect(canon(given)).to eq(stored)
      end
    end

    it 'is idempotent, so the value gvmd returns compares equal to itself' do
      stored = canon('apply_overrides=1 min_qod=70')
      expect(canon(stored)).to eq(stored)
    end

    it 'rejects rows=-1, which gvmd replaces with Max Rows Per Page' do
      expect { canon('rows=-1 first=1 sort=name') }.to raise_error(Puppet::ResourceError, %r{rows=-1})
    end

    it 'treats an empty comment as unset' do
      r = provider.canonicalize(context, [{ name: 'f', comment: '  ' }]).first
      expect(r[:comment]).to be_nil
    end
  end

  describe '#get' do
    it 'reads filters and ignores the <filters> element describing the query' do
      doc = xml_doc(<<~XML)
        <get_filters_response status="200">
          <filter id="#{id}">
            <owner><name>admin</name></owner>
            <name>Results (overrides applied)</name>
            <comment></comment>
            <type>result</type>
            <term>apply_overrides=1 min_qod=70 first=1 rows=10 sort=name</term>
          </filter>
          <filters id=""><term>rows=1000 first=1 sort=name</term></filters>
        </get_filters_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)

      expect(provider.get(context)).to eq([{
                                            ensure: 'present',
                                            name: 'Results (overrides applied)',
                                            filter_type: 'result',
                                            term: 'apply_overrides=1 min_qod=70 first=1 rows=10 sort=name',
                                            comment: nil,
                                          }])
    end

    it 'asks for every filter, not the first ten' do
      expect(provider).to receive(:transport_command).with(context, '<get_filters filter="rows=-1"/>').and_return(nil)
      provider.get(context)
    end
  end

  describe '#create' do
    it 'sends name, comment, term and type, escaped' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to eq('<create_filter><name>a&amp;b</name><comment></comment>' \
                          '<term>name~&lt;x&gt; first=1</term><type>result</type></create_filter>')
      end
      provider.create(context, 'a&b', { term: 'name~<x> first=1', filter_type: 'result' })
    end
  end

  describe '#update' do
    it 'modifies by the id resolved from the name' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'filter', 'f').and_return(id)
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to start_with("<modify_filter filter_id=\"#{id}\">")
        expect(xml).to include('<comment>c</comment>', '<term>t</term>', '<type>report</type>')
      end
      provider.update(context, 'f', { term: 't', comment: 'c', filter_type: 'report' })
    end

    it 'raises when the filter has gone' do
      allow(provider).to receive(:resolve_name_to_id).and_return(nil)
      expect { provider.update(context, 'f', { term: 't' }) }.to raise_error(Puppet::ResourceError, %r{not found})
    end

    it 'clears the comment with an empty element when delete_properties lists it' do
      allow(provider).to receive(:resolve_name_to_id).with(context, 'filter', 'f').and_return(id)
      expect(provider).to receive(:transport_command)
        .with(context, "<modify_filter filter_id=\"#{id}\"><comment></comment><term>t</term><type>result</type></modify_filter>")
      provider.update(context, 'f', { term: 't', delete_properties: ['comment'] })
    end
  end

  describe '#delete' do
    it 'deletes ultimately by id' do
      allow(provider).to receive(:resolve_name_to_id).and_return(id)
      expect(provider).to receive(:transport_command).with(context, "<delete_filter filter_id=\"#{id}\" ultimate=\"1\"/>")
      provider.delete(context, 'f')
    end
  end
end
