# frozen_string_literal: true

Puppet::Type.type(:gvm_admin).provide(:gvm_admin) do
  desc 'Manages the GVM admin user via gvmd CLI with array-based execution (no shell).'

  def exists?
    out = Puppet::Util::Execution.execute(
      [resource[:gvmd_bin], '--get-users'],
      uid:        resource[:gvm_user],
      gid:        resource[:gvm_group],
      failonfail: false,
      combine:    false,
    )
    # gvmd --get-users prints one user per line. Match the first whitespace-
    # delimited field so detection still works if gvmd ever appends columns.
    out.to_s.each_line.any? { |line| line.split(%r{\s+}).reject(&:empty?).first == resource[:name] }
  rescue Puppet::ExecutionFailure => error
    raise Puppet::Error, "Failed to query GVM users: #{error.message}"
  end

  def create
    password = resource[:password]
    password = password.unwrap if password.respond_to?(:unwrap)
    # Array execution bypasses the shell entirely. sensitive: true prevents
    # Puppet from logging the argv (which contains --password=) at debug level.
    # The password still appears in the process argument list (gvmd CLI
    # limitation) but is never in the Puppet catalog command property.
    Puppet::Util::Execution.execute(
      [resource[:gvmd_bin], "--create-user=#{resource[:name]}", "--password=#{password}"],
      uid:        resource[:gvm_user],
      gid:        resource[:gvm_group],
      failonfail: true,
      sensitive:  true,
    )
  end

  def destroy
    Puppet::Util::Execution.execute(
      [resource[:gvmd_bin], "--delete-user=#{resource[:name]}"],
      uid:        resource[:gvm_user],
      gid:        resource[:gvm_group],
      failonfail: true,
    )
  end
end
