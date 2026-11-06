# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'greenbone::to_transport_yaml', type: :puppet_function do
  # rspec-puppet's `.and_return` only does equality, so we drive the function
  # via execute(...) and run normal expectations on the YAML it returns.
  let(:function) { find_function }

  it 'returns a String' do
    expect(function.execute('admin', 'secret', '/run/gvmd/sock')).to be_a(String)
  end

  it 'produces YAML that YAML.safe_load parses back to the original values' do
    yaml = function.execute('admin', 'secret', '/run/gvmd/sock')
    expect(YAML.safe_load(yaml)).to eq(
      'user' => 'admin', 'password' => 'secret', 'socket' => '/run/gvmd/sock',
    )
  end

  it 'unwraps a Sensitive password and serialises the cleartext value' do
    yaml = function.execute('admin', sensitive('s3cr3t'), '/run/gvmd/sock')
    expect(YAML.safe_load(yaml)['password']).to eq('s3cr3t')
  end

  context 'when the password contains YAML-significant characters' do
    [
      ['colon and space',   'host: localhost'],
      ['single quotes',     "it's a 'quoted' value"],
      ['double quotes',     'say "hello"'],
      ['curly braces',      '{inline: map}'],
      ['square brackets',   '[inline, sequence]'],
      ['hash sign',         '# not a comment'],
      ['pipe/literal',      "line1\nline2\nline3"],
      ['null bytes',        "pass\x00word"],
      ['backslash',         'C:\\Users\\admin'],
    ].each do |desc, password|
      it "round-trips #{desc} without corruption" do
        yaml = function.execute('u', password, '/s')
        expect(YAML.safe_load(yaml)['password']).to eq(password)
      end
    end
  end

  context 'when the user contains special characters' do
    it 'round-trips a user with double-quote characters' do
      user = 'admin"quoted'
      yaml = function.execute(user, 'pass', '/s')
      expect(YAML.safe_load(yaml)['user']).to eq(user)
    end
  end

  context 'when the socket path contains special characters' do
    it 'round-trips a socket path with colons and spaces' do
      socket = '/run/gvmd/gvmd: main.sock'
      yaml = function.execute('u', 'p', socket)
      expect(YAML.safe_load(yaml)['socket']).to eq(socket)
    end
  end
end
