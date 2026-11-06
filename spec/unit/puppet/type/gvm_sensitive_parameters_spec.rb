# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'sensitive attribute redaction' do
  # Every attribute the schemas flag as `sensitive: true`, with a usable value.
  # The final example per type asserts this stays exhaustive.
  secrets = {
    gvm_user: { password: 'hunter2' },
  }.freeze

  base = {
    gvm_user: { title: 'alice', name: 'alice' },
  }.freeze

  secrets.each do |type_name, attributes|
    describe type_name do
      let(:type) do
        require "puppet/type/#{type_name}"
        Puppet::Type.type(type_name)
      end

      attributes.each do |attribute, value|
        # A Resource API `sensitive: true` flag never reaches the RAL on its own,
        # so Puppet would print the value wherever it formats the attribute.
        it "marks #{attribute} sensitive on the RAL so Puppet redacts it" do
          resource = type.new(base[type_name].merge(attribute => value))
          expect(resource.parameter(attribute).sensitive).to be true
        end

        # Sensitive() in the manifest must not be what saves us: a Hiera/eyaml
        # lookup hands the type a plain String.
        it "redacts #{attribute} when it is declared as a plain value" do
          resource = type.new(base[type_name].merge(attribute => value))
          expect(resource.parameter(attribute).format('%s', value)).to eq('[redacted]')
        end
      end

      it 'leaves non-sensitive attributes unredacted' do
        resource = type.new(base[type_name])
        insensitive = type.type_definition.attributes.reject { |_name, options| options[:sensitive] }.keys
        expect(insensitive.select { |name| resource.parameter(name)&.sensitive }).to be_empty
      end

      it 'covers every attribute the schema flags as sensitive' do
        flagged = type.type_definition.attributes.select { |_name, options| options[:sensitive] == true }.keys
        expect(flagged).to match_array(attributes.keys)
      end
    end
  end

  # gvm_user is the only Resource API type with a secret. This keeps it that
  # way unless a new one is registered with the helper.
  it 'flags no other gvm_* Resource API attribute as sensitive' do
    flagged = Dir[File.expand_path('../../../../lib/puppet/type/gvm_*.rb', __dir__)].map { |f| File.basename(f, '.rb') }.select do |name|
      require "puppet/type/#{name}"
      type = Puppet::Type.type(name.to_sym)
      type.respond_to?(:type_definition) && type.type_definition.attributes.any? { |_n, o| o[:sensitive] }
    end
    expect(flagged).to eq(['gvm_user'])
  end
end
