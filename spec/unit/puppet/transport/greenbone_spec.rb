# frozen_string_literal: true

require 'spec_helper'
require 'puppet/transport/greenbone'

RSpec.describe Puppet::Transport::Greenbone do
  subject(:transport) do
    described_class.new(context, socket: '/run/gvmd/gvmd.sock', user: 'admin', password: 'secret')
  end

  let(:context) do
    instance_double('Puppet::ResourceApi::BaseContext', debug: nil)
  end

  # Returns a stateful double whose #closed? tracks #close calls, as the
  # transport's close() method checks @socket.closed? on subsequent calls.
  def make_fake_socket(name = 'socket')
    closed = false
    dbl = instance_double(UNIXSocket, name)
    allow(dbl).to receive(:closed?) { closed }
    allow(dbl).to receive(:close) { closed = true }
    # write_nonblock returns the number of bytes written; returning the full
    # length makes the transport's write loop complete in a single iteration.
    allow(dbl).to receive(:write_nonblock) { |data| data.bytesize }
    allow(dbl).to receive(:flush)
    dbl
  end

  # ─── escape_xml ──────────────────────────────────────────────────────────────

  describe '#escape_xml (private)' do
    {
      '&'        => '&amp;',
      '<'        => '&lt;',
      '>'        => '&gt;',
      '"'        => '&quot;',
      "'"        => '&apos;',
      '<b>&"\'>' => '&lt;b&gt;&amp;&quot;&apos;&gt;',
      ''         => '',
    }.each do |input, expected|
      it "escapes #{input.inspect} → #{expected.inspect}" do
        expect(transport.send(:escape_xml, input)).to eq(expected)
      end
    end

    it 'does not double-escape an already-escaped entity' do
      # Verify &amp; is escaped to &amp;amp; (caller is responsible for escaping once)
      expect(transport.send(:escape_xml, '&amp;')).to eq('&amp;amp;')
    end
  end

  # ─── read_response: timeout ──────────────────────────────────────────────────

  describe '#read_response (private) on read timeout' do
    it 'raises Puppet::ResourceError and closes the socket' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      allow(IO).to receive(:select).and_return(nil)

      expect { transport.send(:read_response, sock) }
        .to raise_error(Puppet::ResourceError, %r{GMP read timeout after 30s})

      expect(sock.closed?).to be true
      expect(transport.instance_variable_get(:@socket)).to be_nil
    end
  end

  # ─── read_response: size limit ───────────────────────────────────────────────

  describe '#read_response (private) on size-limit breach' do
    it 'raises Puppet::ResourceError and closes the socket' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      allow(IO).to receive(:select).and_return([[sock], nil, nil])
      oversized = 'x' * (described_class::MAX_RESPONSE_BYTES + 1)
      allow(sock).to receive(:readpartial).and_return(oversized)

      expect { transport.send(:read_response, sock) }
        .to raise_error(Puppet::ResourceError, %r{MiB limit})

      expect(sock.closed?).to be true
    end
  end

  # ─── read_response: parse error ──────────────────────────────────────────────

  describe '#read_response (private) on malformed XML' do
    it 'raises Puppet::ResourceError and closes the socket' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      allow(IO).to receive(:select).and_return([[sock], nil, nil])
      # Has closing tag so the loop exits, but the XML is structurally invalid.
      allow(sock).to receive(:readpartial).and_return("<result status='200'><<bad\x00</result>")

      expect { transport.send(:read_response, sock) }
        .to raise_error(Puppet::ResourceError, %r{parse error})

      expect(sock.closed?).to be true
    end
  end

  # ─── write_with_timeout: timeout ─────────────────────────────────────────────

  describe '#write_with_timeout (private) on write timeout' do
    it 'raises Puppet::ResourceError and closes the socket' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      # Socket buffer is never writable: write_nonblock signals EAGAIN and the
      # subsequent IO.select wait times out.
      allow(sock).to receive(:write_nonblock).and_raise(IO::EAGAINWaitWritable)
      allow(IO).to receive(:select).with(nil, [sock], nil, anything).and_return(nil)

      expect { transport.send(:write_with_timeout, sock, '<command/>') }
        .to raise_error(Puppet::ResourceError, %r{GMP write timeout after 10s})

      expect(sock.closed?).to be true
    end
  end

  # ─── read_response: successful round-trip ────────────────────────────────────

  describe '#read_response (private) with a valid self-closing response' do
    it 'returns a parsed REXML::Document' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      allow(IO).to receive(:select).and_return([[sock], nil, nil])
      allow(sock).to receive(:readpartial).and_return('<authenticate_response status="200"/>')

      result = transport.send(:read_response, sock)
      expect(result).to be_a(REXML::Document)
      expect(result.root.name).to eq('authenticate_response')
    end
  end

  describe '#read_response (private) with a valid open/close response' do
    it 'returns a parsed REXML::Document' do
      sock = make_fake_socket
      transport.instance_variable_set(:@socket, sock)
      allow(IO).to receive(:select).and_return([[sock], nil, nil])
      allow(sock).to receive(:readpartial).and_return(
        '<get_tasks_response status="200"><task id="abc"/></get_tasks_response>',
      )

      result = transport.send(:read_response, sock)
      expect(result.root.attributes['status']).to eq('200')
    end
  end

  # ─── passwords with unusual content ──────────────────────────────────────────

  describe 'with a password containing XML-special characters' do
    it 'wraps the password safely in the authenticate XML' do
      tricky = described_class.new(
        context,
        socket: '/s', user: 'u', password: %(<pw "&'<>/>),
      )
      # authenticate builds XML with the password inline — escape_xml must prevent injection
      xml_sent = nil
      sock = make_fake_socket
      allow(sock).to receive(:write_nonblock) { |data|
        xml_sent = data
        data.bytesize
      }
      allow(IO).to receive(:select).and_return([[sock], nil, nil])
      allow(sock).to receive(:readpartial).and_return('<authenticate_response status="200"/>')

      tricky.instance_variable_set(:@socket, sock)
      tricky.send(:authenticate, context)

      # Password <pw "&'<>/> escaped in order &,<,>,",' → quote precedes amp here.
      expect(xml_sent).to include('&lt;pw &quot;&amp;&apos;&lt;&gt;/&gt;')
      expect(xml_sent).not_to include('<pw')
    end
  end

  # ─── command: the GMP round trip ─────────────────────────────────────────────

  describe '#command' do
    # What each scripted socket was sent, in order.
    let(:sent) { Hash.new { |h, k| h[k] = [] } }
    let(:auth_ok) { '<authenticate_response status="200" status_text="OK"/>' }

    # A socket that records what is written and answers each read with the
    # next queued response, or raises it when it is an exception class.
    def scripted_socket(*responses)
      sock = make_fake_socket
      allow(sock).to receive(:write_nonblock) do |data|
        sent[sock] << data
        data.bytesize
      end
      allow(sock).to receive(:readpartial) do
        reply = responses.shift
        raise reply if reply.is_a?(Class)

        reply
      end
      sock
    end

    before(:each) do
      allow(IO).to receive(:select).and_return([[], [], []])
    end

    it 'connects, authenticates once and returns the parsed response' do
      sock = scripted_socket(auth_ok, '<get_tasks_response status="200"><task id="t"/></get_tasks_response>',
                             '<get_targets_response status="200"/>')
      expect(UNIXSocket).to receive(:new).once.with('/run/gvmd/gvmd.sock').and_return(sock)

      doc = transport.command(context, '<get_tasks/>')
      transport.command(context, '<get_targets/>')

      expect(doc.root.elements['task'].attributes['id']).to eq('t')
      expect(sent[sock].first).to include('<username>admin</username>', '<password>secret</password>')
      expect(sent[sock].drop(1)).to eq(['<get_tasks/>', '<get_targets/>'])
    end

    it 'unwraps a Sensitive password for the handshake' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('s3cret')
      t = described_class.new(context, socket: '/s', user: 'admin', password: sensitive)
      sock = scripted_socket(auth_ok, '<get_tasks_response status="200"/>')
      allow(UNIXSocket).to receive(:new).and_return(sock)
      t.command(context, '<get_tasks/>')
      expect(sent[sock].first).to include('<password>s3cret</password>')
    end

    it 'raises the GMP status and text for a non-2xx answer' do
      sock = scripted_socket(auth_ok, %(<create_target_response status="400" status_text="Target exists already"/>))
      allow(UNIXSocket).to receive(:new).and_return(sock)
      expect { transport.command(context, '<create_target/>') }
        .to raise_error(Puppet::ResourceError, 'GMP error 400: Target exists already')
    end

    it 'raises when authentication is refused' do
      allow(UNIXSocket).to receive(:new).and_return(scripted_socket('<authenticate_response status="400"/>'))
      expect { transport.command(context, '<get_tasks/>') }
        .to raise_error(Puppet::ResourceError, 'GMP authentication failed (status 400)')
    end

    it 'names the socket when gvmd is not listening' do
      allow(UNIXSocket).to receive(:new).and_raise(Errno::ENOENT)
      expect { transport.command(context, '<get_tasks/>') }
        .to raise_error(Puppet::ResourceError, %r{Cannot connect to gvmd socket /run/gvmd/gvmd.sock})
    end

    # gvmd closes an idle connection; the stale socket fails on its next use.
    it 'reconnects and resends when the server closed the connection before the write' do
      stale = scripted_socket(auth_ok)
      allow(stale).to receive(:write_nonblock).and_return(auth_ok.bytesize)
      allow(stale).to receive(:write_nonblock).with('<modify_task/>').and_raise(Errno::EPIPE)
      fresh = scripted_socket(auth_ok, '<modify_task_response status="200"/>')
      allow(UNIXSocket).to receive(:new).and_return(stale, fresh)

      expect(transport.command(context, '<modify_task/>').root.name).to eq('modify_task_response')
      expect(sent[fresh].last).to eq('<modify_task/>')
    end

    it 'replays a read whose answer was cut off' do
      first = scripted_socket(auth_ok, EOFError)
      second = scripted_socket(auth_ok, '<get_tasks_response status="200"/>')
      allow(UNIXSocket).to receive(:new).and_return(first, second)
      expect(transport.command(context, '<get_tasks/>').root.name).to eq('get_tasks_response')
    end

    # The server may already have applied it; a replay could create twice.
    it 'does not replay a write whose answer was cut off' do
      sock = scripted_socket(auth_ok, EOFError)
      expect(UNIXSocket).to receive(:new).once.and_return(sock)
      expect { transport.command(context, '<create_task/>') }.to raise_error(EOFError)
    end
  end

  describe '#write_with_timeout (private)' do
    it 'keeps writing after a partial write until every byte is sent' do
      sock = make_fake_socket
      chunks = []
      allow(sock).to receive(:write_nonblock) do |data|
        chunks << data
        [data.bytesize, 3].min
      end
      transport.send(:write_with_timeout, sock, 'abcdefgh')
      expect(chunks).to eq(['abcdefgh', 'defgh', 'gh'])
    end

    it 'waits for the socket to drain and retries' do
      sock = make_fake_socket
      attempts = 0
      allow(sock).to receive(:write_nonblock) do |data|
        attempts += 1
        raise IO::EAGAINWaitWritable if attempts == 1

        data.bytesize
      end
      expect(IO).to receive(:select).with(nil, [sock], nil, kind_of(Numeric)).and_return([[], [sock], []])
      transport.send(:write_with_timeout, sock, 'abc')
      expect(attempts).to eq(2)
    end
  end

  describe '#close' do
    it 'is safe to call without a connection and twice' do
      expect { 2.times { transport.close } }.not_to raise_error
    end
  end
end
