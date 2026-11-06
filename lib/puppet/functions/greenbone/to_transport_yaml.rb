# frozen_string_literal: true

require 'yaml'

# Serialise the three GMP transport credential fields to a YAML document using
# Ruby's Psych library. This avoids handwritten quoting in an EPP template,
# which cannot safely round-trip passwords that contain single/double quotes,
# colons, newlines, or other YAML-significant characters.
#
# The password may be passed as a Sensitive[String]; it is unwrapped inside the
# function so the cleartext value never has to be unwrapped in the manifest
# scope. The caller should wrap the returned YAML in Sensitive() when writing
# it to a file so it does not leak into reports.
Puppet::Functions.create_function(:'greenbone::to_transport_yaml') do
  dispatch :to_transport_yaml do
    param 'String', :user
    param 'Variant[String, Sensitive[String]]', :password
    param 'String', :socket
    return_type 'String'
  end

  def to_transport_yaml(user, password, socket)
    plaintext = password.respond_to?(:unwrap) ? password.unwrap : password
    { 'user' => user, 'password' => plaintext, 'socket' => socket }.to_yaml
  end
end
