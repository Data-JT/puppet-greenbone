# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'greenbone' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:config_file) { '/etc/puppetlabs/puppet/gvm_transport.yaml' }
      let(:params) do
        {
          password: sensitive('secret'),
          repo_key_id: '0123456789ABCDEF0123456789ABCDEF01234567',
          config_file: config_file,
        }
      end

      it { is_expected.to compile.with_all_deps }

      # The default path follows the AGENT's confdir (fact greenbone_confdir),
      # not the compiling server's $settings::confdir: an AIO server compiling
      # for a Debian agent must not put the file under /etc/puppetlabs/puppet.
      context 'without config_file, when the agent reports its confdir' do
        let(:facts) { os_facts.merge(greenbone_confdir: '/etc/puppet') }
        let(:params) do
          {
            password: sensitive('secret'),
            repo_key_id: '0123456789ABCDEF0123456789ABCDEF01234567',
          }
        end

        it { is_expected.to contain_file('/etc/puppet/gvm_transport.yaml').with_mode('0600') }
        it { is_expected.not_to contain_file('/etc/puppetlabs/puppet/gvm_transport.yaml') }
      end

      it { is_expected.to contain_apt__source('greenbone-community-edition') }

      it 'manages the transport credentials file with 0600' do
        is_expected.to contain_file(config_file).with(
          ensure: 'file',
          owner: 'root',
          group: 'root',
          mode: '0600',
        )
      end

      # Class parameters user/password/socket map 1:1 onto the transport keys.
      context 'with user and socket set' do
        let(:params) { super().merge(user: 'puppet', socket: '/run/gvmd/custom.sock') }

        it 'writes them under the same keys in the transport file' do
          content = catalogue.resource('File', config_file)[:content]
          expect(YAML.safe_load(content)).to eq(
            'user' => 'puppet', 'password' => 'secret', 'socket' => '/run/gvmd/custom.sock',
          )
        end
      end

      it { is_expected.to contain_group('gvm').with_system(true) }
      it { is_expected.to contain_user('gvm').with_system(true) }
      it { is_expected.to contain_package('gvmd').with_tag('greenbone') }

      context 'with manage_repo => false' do
        let(:params) { super().merge(manage_repo: false) }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_apt__source('greenbone-community-edition') }
      end

      context "with install_method => 'docker'" do
        let(:params) { super().merge(install_method: 'docker') }

        # Regression guard: the public-release refactor once narrowed
        # install_method back to Enum['unmanaged'], which broke catalog
        # compilation on nodes using docker mode. This must keep compiling.
        it { is_expected.to compile.with_all_deps }

        # docker mode skips all OS-level resources (your own profile
        # runs the Community Container compose stack)...
        it { is_expected.not_to contain_apt__source('greenbone-community-edition') }
        it { is_expected.not_to contain_group('gvm') }
        it { is_expected.not_to contain_user('gvm') }
        it { is_expected.not_to contain_package('gvmd') }

        # ...but still manages the GMP transport credentials file so the
        # gvm_* providers keep working.
        it { is_expected.to contain_file(config_file).with_ensure('file') }
      end

      context 'with an invalid install_method' do
        let(:params) { super().merge(install_method: 'helm') }

        it { is_expected.to compile.and_raise_error(%r{install_method}) }
      end

      # The providers read the transport file from an absolute path, and the
      # repository values go to apt verbatim.
      {
        config_file:     'gvm_transport.yaml',
        socket:          'run/gvmd/gvmd.sock',
        user:            '',
        repo_location:   'dl.greenbone.net/repo/CE/stable',
        repo_key_source: 'file:///tmp/key.gpg',
        data_dir:        'var/lib/gvm',
        gvm_user:        'gvm user',
      }.each do |param, value|
        context "with an invalid #{param}" do
          let(:params) { super().merge(param => value) }

          it { is_expected.to compile.and_raise_error(%r{#{param}}) }
        end
      end

      context 'with an http repository and a custom absolute config_file' do
        let(:params) do
          super().merge(repo_location: 'http://apt.example.org/greenbone', config_file: '/etc/puppetlabs/puppet/gvm_transport.yaml')
        end

        it { is_expected.to contain_file('/etc/puppetlabs/puppet/gvm_transport.yaml') }
      end
    end
  end

  context 'when codename fact is absent and manage_repo is true' do
    let(:facts) do
      {
        'os' => {
          'family' => 'Debian',
          'name' => 'Debian',
          'release' => { 'major' => '12', 'full' => '12' },
          'distro' => {},
        },
      }
    end
    let(:params) { { password: sensitive('secret') } }

    it 'fails because repo_release cannot be determined' do
      is_expected.to compile.and_raise_error(%r{repo_release could not be determined})
    end
  end
end
