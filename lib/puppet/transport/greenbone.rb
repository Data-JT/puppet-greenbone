# frozen_string_literal: true

require 'socket'
require 'rexml/document'

# @api private
module Puppet::Transport; end

# Transport for Greenbone Vulnerability Manager via the GMP Unix socket.
#
# GMP is a synchronous XML protocol: the client sends one XML command,
# the server responds with one XML document. Authentication happens once
# per connection via <authenticate>.
class Puppet::Transport::Greenbone
  MAX_RESPONSE_BYTES = 64 * 1024 * 1024 # 64 MiB
  READ_TIMEOUT       = 30 # seconds, covers the full response
  WRITE_TIMEOUT      = 10 # seconds

  def initialize(context, connection_info)
    @socket_path = connection_info[:socket]
    @user        = connection_info[:user]
    pw = connection_info[:password]
    @password    = pw.respond_to?(:unwrap) ? pw.unwrap : pw.to_s
    @socket      = nil
    context.debug("Initialized Greenbone GMP transport for #{@socket_path}")
  end

  # Send a GMP command (REXML::Element or XML string) and return parsed response.
  # gvmd closes the connection after each session, and @socket.closed? cannot
  # detect that until the next read, so the first use of a stale socket fails.
  #
  # Errno::EPIPE happens on the write side: gvmd closed the connection before
  # receiving the command, so replaying is always safe. EOFError can happen on
  # the read side after the command was sent — the server may already have
  # applied it — so we only replay idempotent reads (get_*) to avoid issuing a
  # duplicate create/modify/delete.
  def command(context, xml)
    xml_str = xml.is_a?(String) ? xml : xml.to_s
    context.debug("GMP >> #{gmp_op_name(xml_str)}")
    _send_and_recv(context, xml_str)
  rescue Errno::EPIPE
    context.debug('GMP connection closed by server before send; reconnecting')
    close
    _send_and_recv(context, xml_str)
  rescue EOFError
    raise unless idempotent_op?(xml_str)

    context.debug('GMP connection closed by server; reconnecting idempotent read')
    close
    _send_and_recv(context, xml_str)
  end

  def close
    return unless @socket

    @socket.close rescue nil # rubocop:disable Style/RescueModifier
    @socket = nil
  end

  private

  def _send_and_recv(context, xml_str)
    sock = socket(context)
    write_with_timeout(sock, xml_str)
    response = read_response(sock)
    root = response.root
    context.debug("GMP << #{gmp_op_name(root&.name)} status=#{root&.attributes&.[]('status')}")
    check_status!(response)
    response
  end

  def socket(context)
    return @socket if @socket && !@socket.closed?

    @socket = UNIXSocket.new(@socket_path)
    authenticate(context)
    @socket
  rescue Errno::ENOENT, Errno::ECONNREFUSED => error
    raise Puppet::ResourceError, "Cannot connect to gvmd socket #{@socket_path}: #{error.message}"
  end

  def authenticate(context)
    context.debug('GMP authenticating')
    xml = '<authenticate><credentials>' \
          "<username>#{escape_xml(@user)}</username>" \
          "<password>#{escape_xml(@password)}</password>" \
          '</credentials></authenticate>'
    write_with_timeout(@socket, xml)
    response = read_response(@socket)
    status = response.root&.attributes&.[]('status')
    raise Puppet::ResourceError, "GMP authentication failed (status #{status})" unless status == '200'
  end

  # Write the full payload, bounding the *total* duration (not just initial
  # writability) with a monotonic deadline. Uses write_nonblock in a loop so a
  # slow-draining socket buffer cannot block past WRITE_TIMEOUT.
  def write_with_timeout(sock, data)
    remaining = data.b
    deadline  = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WRITE_TIMEOUT

    until remaining.empty?
      timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if timeout <= 0
        close
        raise Puppet::ResourceError, "GMP write timeout after #{WRITE_TIMEOUT}s"
      end

      begin
        written   = sock.write_nonblock(remaining)
        remaining = remaining.byteslice(written..) || ''
      rescue IO::WaitWritable
        unless IO.select(nil, [sock], nil, timeout)
          close
          raise Puppet::ResourceError, "GMP write timeout after #{WRITE_TIMEOUT}s"
        end
        retry
      rescue Errno::EINTR
        retry
      end
    end
  end

  # Read bytes from socket until we have a complete single-root XML document.
  # GMP is synchronous so there is always exactly one response per command.
  # Enforces READ_TIMEOUT across the full response and MAX_RESPONSE_BYTES to
  # guard against a hung or adversarial gvmd. Closes the socket on any violation.
  def read_response(sock)
    buffer   = +''
    root_tag = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + READ_TIMEOUT

    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      unless remaining > 0 && IO.select([sock], nil, nil, remaining)
        close
        raise Puppet::ResourceError, "GMP read timeout after #{READ_TIMEOUT}s"
      end

      chunk = sock.readpartial(65_536)
      buffer << chunk

      if buffer.bytesize > MAX_RESPONSE_BYTES
        close
        raise Puppet::ResourceError, "GMP response exceeded #{MAX_RESPONSE_BYTES / (1024 * 1024)} MiB limit"
      end

      unless root_tag
        match = buffer.match(%r{<([A-Za-z_][A-Za-z0-9_]*)[\s/>]})
        next unless match

        root_tag = match[1]
      end

      # Self-closing root (e.g. <authenticate_response status="200"/>).
      # Require a space or '/' immediately after the tag name so a child
      # element whose name merely starts with the root name (e.g. <target_x/>
      # inside root <target>) does not falsely terminate the read.
      break if buffer.match?(%r{<#{Regexp.escape(root_tag)}(\s[^>]*)?/>})
      # Root element closed
      break if buffer.include?("</#{root_tag}>")
    end

    REXML::Document.new(buffer)
  rescue REXML::ParseException => error
    close
    safe_snippet = buffer[0, 200].gsub(%r{[[:cntrl:]]}, '?')
    raise Puppet::ResourceError, "GMP response parse error: #{error.message}\nBuffer: #{safe_snippet}"
  end

  def check_status!(doc)
    root = doc.root
    return unless root

    attributes = root.attributes
    status = attributes['status']
    return if !status || status.start_with?('2')

    text = attributes['status_text'].to_s.gsub(%r{[[:cntrl:]]}, '')
    raise Puppet::ResourceError, "GMP error #{status}: #{text}"
  end

  def gmp_op_name(xml)
    xml.to_s.match(%r{\A<([A-Za-z_][A-Za-z0-9_]*)})&.[](1) || '?'
  end

  # Whether a command is a safe-to-replay read. Only get_* queries and the
  # authentication handshake are idempotent; create/modify/delete are not.
  def idempotent_op?(xml_str)
    op = gmp_op_name(xml_str)
    op.start_with?('get_') || op == 'authenticate'
  end

  def escape_xml(str)
    str.to_s
       .gsub('&', '&amp;')
       .gsub('<', '&lt;')
       .gsub('>', '&gt;')
       .gsub('"', '&quot;')
       .gsub("'", '&apos;')
  end
end
