# frozen_string_literal: true

# Registers the managed Greenbone transport file as an automatic dependency.
module Puppet::Type::GvmTransportAutorequire
  def self.register(type_name)
    Puppet::Type.type(type_name).autorequire(:file) do
      File.join(Puppet.settings[:confdir], 'gvm_transport.yaml')
    end
  end
end
