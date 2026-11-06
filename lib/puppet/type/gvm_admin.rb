# frozen_string_literal: true

Puppet::Type.newtype(:gvm_admin) do
  @doc = <<~DOC
    Ensures the initial GVM admin user exists via gvmd CLI. Uses array-based
    execution (no shell) to prevent injection. The password is marked
    sensitive and never stored as plaintext in the catalog. Note: gvmd CLI
    passes --password in argv on creation; this is an unavoidable gvmd
    limitation. Rotate the bootstrap password after provisioning.
  DOC

  newproperty(:ensure) do
    desc 'Whether the user should exist. present creates it with `gvmd --create-user`; absent deletes it with `gvmd --delete-user`.'

    newvalue(:present) do
      provider.create
    end
    newvalue(:absent) do
      provider.destroy
    end

    def retrieve
      provider.exists? ? :present : :absent
    end
  end

  newparam(:name, namevar: true) do
    desc 'Name of the GVM user. Must not contain whitespace, <, >, &, or quotes.'

    validate do |value|
      raise ArgumentError, 'GVM username must be a non-empty string' if value.to_s.strip.empty?
      raise ArgumentError, "GVM username contains invalid characters: #{value}" if value.match?(%r{[[:space:]<>&"']})
    end
  end

  newparam(:password) do
    sensitive true
    desc 'Admin password. Marked sensitive: not logged or stored as plaintext in catalog.'
  end

  newparam(:gvmd_bin) do
    desc 'Absolute path to the gvmd binary used to list, create and delete the user.'

    defaultto '/usr/sbin/gvmd'
    validate do |value|
      raise ArgumentError, "gvmd_bin must be an absolute path, got: #{value}" unless value.start_with?('/')
    end
  end

  newparam(:gvm_user) do
    desc 'System user gvmd is run as, so it reaches its database with the right identity.'

    defaultto 'gvm'
  end

  newparam(:gvm_group) do
    desc 'System group gvmd is run as.'

    defaultto 'gvm'
  end
end
