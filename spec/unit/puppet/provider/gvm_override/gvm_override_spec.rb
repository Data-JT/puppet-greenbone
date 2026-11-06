# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/gvm_override/gvm_override'
require 'rexml/document'

RSpec.describe Puppet::Provider::GvmOverride::GvmOverride do
  subject(:provider) { described_class.allocate }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil, debug: nil) }
  let(:oid) { '1.3.6.1.4.1.25623.1.0.10267' }
  let(:ovid) { 'a1b2c3d4-0000-4000-8000-000000000001' }

  # get_overrides details=1 as gvmd returns it: one managed override, one made
  # by hand in the web UI (no marker), and the <filters> echo of the query.
  let(:listing) do
    REXML::Document.new(<<~XML)
      <get_overrides_response status="200">
        <override id="#{ovid}">
          <nvt oid="#{oid}"><name>SSH Server type and version</name></nvt>
          <text>Assessed: banner only, no vulnerable version.

      [puppet:fp-ssh-banner]</text>
          <hosts>192.0.2.10, 192.0.2.11</hosts>
          <port>22/tcp</port>
          <severity>5.0</severity>
          <new_severity>-1.0</new_severity>
          <active>1</active>
        </override>
        <override id="b1b2c3d4-0000-4000-8000-000000000002">
          <nvt oid="1.3.6.1.4.1.25623.1.0.99999"/>
          <text>Made by hand</text>
          <hosts/><port/><severity/><new_severity>0</new_severity><active>0</active>
        </override>
        <filters id=""><term>rows=-1</term></filters>
      </get_overrides_response>
    XML
  end

  let(:desired) do
    { name: 'fp-ssh-banner', nvt_oid: oid, text: 'Assessed: banner only, no vulnerable version.',
      hosts: '192.0.2.10,192.0.2.11', port: '22/tcp', severity: 5, new_severity: -1, active: true }
  end

  describe '#get' do
    it 'returns an empty array when the transport is not configured' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    # details=1 is what makes gvmd include <hosts> and <port>; rows=-1 lifts
    # the ten-row page limit.
    it 'asks for every override with details' do
      expect(provider).to receive(:transport_command)
        .with(context, '<get_overrides filter="rows=-1" details="1"/>').and_return(listing)
      provider.get(context)
    end

    it 'reads only marked overrides, with the title recovered from the marker' do
      allow(provider).to receive(:transport_command).and_return(listing)
      expect(provider.get(context)).to eq([{
                                            ensure: 'present',
                                            name: 'fp-ssh-banner',
                                            text: 'Assessed: banner only, no vulnerable version.',
                                            nvt_oid: oid,
                                            hosts: '192.0.2.10,192.0.2.11',
                                            port: '22/tcp',
                                            severity: 5,
                                            new_severity: -1,
                                            active: true,
                                          }])
    end

    it 'reads a fractional severity as a Float and an empty one as unset' do
      doc = REXML::Document.new(<<~XML)
        <get_overrides_response status="200">
          <override id="#{ovid}"><nvt oid="#{oid}"/><text>t [puppet:x]</text>
            <hosts/><port/><severity/><new_severity>6.5</new_severity><active>0</active></override>
        </get_overrides_response>
      XML
      allow(provider).to receive(:transport_command).and_return(doc)
      expect(provider.get(context).first).to include(hosts: nil, port: nil, severity: nil, new_severity: 6.5, active: false)
    end
  end

  describe '#canonicalize' do
    it 'strips the text and normalizes the host list so neither churns' do
      result = provider.canonicalize(context, [{ name: 'x', text: "  why\r\n", hosts: ' a , b,,c ', new_severity: 0 }])
      expect(result.first).to include(text: 'why', hosts: 'a,b,c')
    end

    it 'treats an empty host list as unset' do
      expect(provider.canonicalize(context, [{ name: 'x', hosts: ' , ' }]).first[:hosts]).to be_nil
    end

    it 'fills in new_severity -1 when it is not declared' do
      expect(provider.canonicalize(context, [{ name: 'x' }]).first[:new_severity]).to eq(-1)
    end

    it 'never replaces a new_severity read from gvmd, even an unparsable one' do
      expect(provider.canonicalize(context, [{ name: 'x', new_severity: nil }]).first[:new_severity]).to be_nil
    end
  end

  describe '#create' do
    it 'sends the marked text, the NVT, the scope and the new severity' do
      expect(provider).to receive(:transport_command).with(
        context,
        '<create_override><text>Assessed: banner only, no vulnerable version.' \
        "\n\n[puppet:fp-ssh-banner]</text><nvt oid=\"#{oid}\"/><hosts>192.0.2.10,192.0.2.11</hosts>" \
        '<port>22/tcp</port><severity>5</severity><new_severity>-1</new_severity><active>-1</active></create_override>',
      )
      provider.create(context, 'fp-ssh-banner', desired)
    end

    it 'omits unset hosts, port and severity, so the override applies everywhere' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).not_to include('<hosts>', '<port>', '<severity>')
        expect(xml).to include('<new_severity>-1</new_severity>')
      end
      provider.create(context, 'fp', desired.merge(hosts: nil, port: nil, severity: nil))
    end

    it 'sends active 0 for an inactive override and keeps fractional severities' do
      expect(provider).to receive(:transport_command) do |_ctx, xml|
        expect(xml).to include('<active>0</active>', '<new_severity>6.5</new_severity>')
      end
      provider.create(context, 'fp', desired.merge(active: false, new_severity: 6.5))
    end

    it 'escapes the text' do
      expect(provider).to receive(:transport_command).with(context, include('<text>a &lt;b&gt; &amp; c'))
      provider.create(context, 'fp', desired.merge(text: 'a <b> & c'))
    end
  end

  describe '#update' do
    it 'finds the override by its marker and resends the full desired state' do
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        xml.start_with?('<get_overrides') ? listing : nil
      end
      provider.update(context, 'fp-ssh-banner', desired.merge(new_severity: 0))
      expect(sent.last).to start_with("<modify_override override_id=\"#{ovid}\"><text>")
      expect(sent.last).to include('<new_severity>0</new_severity>', '<hosts>192.0.2.10,192.0.2.11</hosts>')
    end

    it 'raises when no override carries the marker' do
      allow(provider).to receive(:transport_command).and_return(listing)
      expect { provider.update(context, 'missing', desired) }.to raise_error(Puppet::ResourceError, %r{not found for update: missing})
    end
  end

  describe '#delete' do
    it 'deletes the marked override ultimately by id' do
      sent = []
      allow(provider).to receive(:transport_command) do |_ctx, xml|
        sent << xml
        xml.start_with?('<get_overrides') ? listing : nil
      end
      provider.delete(context, 'fp-ssh-banner')
      expect(sent.last).to eq("<delete_override override_id=\"#{ovid}\" ultimate=\"1\"/>")
    end

    # The safety property of the marker: hand-made overrides are invisible.
    it 'never touches an unmarked override' do
      allow(provider).to receive(:transport_command).and_return(listing)
      expect { provider.delete(context, 'Made by hand') }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end

    it 'raises when the transport is not configured' do
      allow(provider).to receive(:transport_command).and_return(nil)
      expect { provider.delete(context, 'fp-ssh-banner') }.to raise_error(Puppet::ResourceError, %r{not found for delete})
    end

    it 'refuses an id that is not a UUID' do
      bad = REXML::Document.new('<get_overrides_response status="200"><override id="x"><text>[puppet:fp]</text></override></get_overrides_response>')
      allow(provider).to receive(:transport_command).and_return(bad)
      expect { provider.delete(context, 'fp') }.to raise_error(Puppet::ResourceError, %r{invalid UUID})
    end
  end
end
