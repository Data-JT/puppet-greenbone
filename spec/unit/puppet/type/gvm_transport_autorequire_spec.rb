# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/gvm_transport_autorequire'
require 'puppet/type/gvm_target'

RSpec.describe Puppet::Type::GvmTransportAutorequire do
  it 'defines a register module method' do
    expect(described_class).to respond_to(:register)
  end

  it 'registers a file autorequire on the transport yaml for a type' do
    confdir = Puppet.settings[:confdir]
    expected = File.join(confdir, 'gvm_transport.yaml')

    resource = Puppet::Type.type(:gvm_target).new(
      name: 'net',
      hosts: '192.0.2.0/24',
      port_list_name: 'All IANA assigned TCP',
    )

    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource(resource)
    catalog.add_resource(Puppet::Type.type(:file).new(name: expected))

    autoreqs = resource.autorequire(catalog)
    file_titles = autoreqs.map { |edge| edge.source.title }
    expect(file_titles).to include(expected)
  end
end
