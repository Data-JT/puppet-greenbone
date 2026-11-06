# frozen_string_literal: true

require 'spec_helper'

# Every type with an optional property its provider can clear over GMP
# exposes delete_properties, and declares custom_insync so the provider's
# comparison runs at all: without it the attribute would never be in sync.
# The value is the attribute names each type can clear.
TYPES_WITH_DELETE_PROPERTIES = {
  gvm_filter:     { title: { name: 'f', term: 'rows=10' }, clearable: ['comment'] },
  gvm_group:      { title: { name: 'g' }, clearable: ['comment'] },
  gvm_permission: { title: { name: 'p', permission: 'Super', subject_type: 'user', subject_name: 'alice' }, clearable: ['comment'] },
  gvm_schedule:   { title: { name: 's', icalendar: 'BEGIN:VCALENDAR' }, clearable: ['comment'] },
  gvm_target:     { title: { name: 't', hosts: '192.0.2.1' }, clearable: ['comment', 'exclude_hosts'] },
  gvm_task:       { title: { name: 't', target_name: 'x' }, clearable: ['comment', 'schedule_name'] },
  gvm_user:       { title: { name: 'u' }, clearable: ['hosts'] },
}.freeze

RSpec.describe 'delete_properties' do
  TYPES_WITH_DELETE_PROPERTIES.each do |type_name, spec|
    describe type_name.to_s do
      let(:type) do
        require "puppet/type/#{type_name}"
        Puppet::Type.type(type_name)
      end

      it 'declares custom_insync so the provider decides when the deletion is done' do
        expect(type.context.type.feature?('custom_insync')).to be(true)
      end

      it 'is a property, so a pending deletion triggers an update' do
        expect(type.attrtype(:delete_properties)).to eq(:property)
      end

      it "accepts #{spec[:clearable].join(' and ')}" do
        resource = type.new(spec[:title].merge(delete_properties: spec[:clearable]))
        expect(resource[:delete_properties]).to eq(spec[:clearable])
      end

      it 'clears only optional attributes of the type' do
        optional = type.type_definition.attributes.select { |_n, o| o[:type].start_with?('Optional[') }.keys.map(&:to_s)
        expect(optional).to include(*spec[:clearable])
      end

      it 'rejects an attribute the provider cannot clear' do
        expect { type.new(spec[:title].merge(delete_properties: ['name'])) }.to raise_error(Puppet::ResourceError)
      end

      it 'rejects a non-array value' do
        expect { type.new(spec[:title].merge(delete_properties: spec[:clearable].first)) }.to raise_error(Puppet::ResourceError)
      end
    end
  end

  # Through the RAL, as an agent run evaluates it: the Resource API hands the
  # property's insync? to the provider because of custom_insync.
  describe 'evaluated through the RAL' do
    let(:type) do
      require 'puppet/type/gvm_filter'
      Puppet::Type.type(:gvm_filter)
    end
    let(:resource) { type.new(name: 'f', term: 'rows=10', delete_properties: ['comment']) }
    let(:current) { { ensure: 'present', name: 'f', filter_type: 'result', term: 'first=1 rows=10 sort=name' } }

    # An agent run retrieves each resource before checking it, and the Resource
    # API (2.x) caches that state per provider for the run; start every example
    # with an empty cache, as a new run would.
    before(:each) { type.instance_variable_set(:@rsapi_provider_get_cache, nil) }

    it 'is out of sync while gvmd still holds a comment' do
      allow(type.my_provider).to receive(:get).and_return([current.merge(comment: 'old')])
      resource.retrieve
      expect(resource.property(:delete_properties).insync?(nil)).to be(false)
    end

    it 'is in sync once the comment is gone' do
      allow(type.my_provider).to receive(:get).and_return([current.merge(comment: nil)])
      resource.retrieve
      expect(resource.property(:delete_properties).insync?(nil)).to be(true)
    end

    it 'leaves the other properties to the default comparison' do
      allow(type.my_provider).to receive(:get).and_return([current.merge(comment: nil)])
      expect(resource.property(:term).insync?('rows=10 first=1 sort=name')).to be(true)
      expect(resource.property(:term).insync?('rows=20')).to be(false)
    end
  end

  # Types left out on purpose, so adding one is a deliberate decision.
  it 'is not offered where gvmd cannot clear a field or the GMP behaviour is unverified' do
    ['gvm_ldap', 'gvm_override', 'gvm_scan_config', 'gvm_user_setting'].each do |type_name|
      require "puppet/type/#{type_name}"
      expect(Puppet::Type.type(type_name.to_sym).validattr?(:delete_properties)).to be(false), type_name
    end
  end
end
