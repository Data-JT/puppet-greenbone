# @summary Installs and configures Greenbone Community Edition.
#
# Manages the apt repository, packages, system user/group, runtime directories,
# and the GMP transport credentials file used by gvm_* resource providers.
#
# Declare this class before any gvm_* resource types. The database, redis,
# service, feed, and admin sub-classes must be included separately (or via
# the greenbone::server convenience class) so each concern can be ordered
# correctly relative to other catalog resources.
#
# @param install_method
#   How Greenbone is installed on the node.
#   'unmanaged' (default): Greenbone runs natively on the host. Puppet manages
#   the system user/group and runtime directories, plus the apt repository
#   (`manage_repo`) and the packages (`manage_packages`). For a source build or
#   out-of-band packaging, set both of those to false. The apt install path is
#   untested; see the README.
#   'docker': all OS-level resources are skipped (you run the Greenbone
#   Community Container compose stack yourself); only the GMP transport
#   credentials file is managed so the gvm_* providers still work.
# @param manage_repo
#   Whether to manage the apt repository. Disable if you install Greenbone
#   packages through another mechanism (source build, distro packages, etc.).
# @param repo_location
#   Base URL of the apt repository to configure when manage_repo is true.
# @param repo_key_source
#   URL of the GPG signing key for the apt repository.
# @param repo_key_id
#   Expected GPG key fingerprint (long form, 40 hex chars). When set, apt
#   verifies the downloaded key matches this fingerprint before trusting it.
#   Strongly recommended to prevent a compromised origin from substituting
#   a rogue key. Obtain the current fingerprint from the Greenbone release page.
# @param repo_release
#   Apt release component string (e.g. 'bookworm').
# @param packages
#   Hash of package name => ensure value to install.
# @param manage_packages
#   Whether to manage Greenbone OS packages. Disable when Greenbone is
#   installed from source or through an out-of-band packaging mechanism.
# @param gvm_user
#   System user that runs Greenbone services.
# @param gvm_group
#   System group for Greenbone services.
# @param data_dir
#   Base directory for Greenbone persistent data.
# @param log_dir
#   Directory for Greenbone log files.
# @param run_dir
#   Directory for runtime files (sockets, PIDs).
# @param feed_dir
#   Directory where feed data is stored.
# @param user
#   GVM account the providers authenticate with over GMP (the `user` key of
#   the transport file). Not to be confused with `gvm_user`, the system
#   account that runs the services.
# @param password
#   GMP password for `user` (the `password` key of the transport file).
# @param socket
#   Path to the gvmd Unix socket (the `socket` key of the transport file).
# @param config_file
#   Path where the transport credentials YAML is written. It must be the path
#   the agent's providers read: `<agent confdir>/gvm_transport.yaml`
#   (`Puppet[:confdir]` on the node). The default is the agent's own confdir,
#   from the `greenbone_confdir` fact; `$settings::confdir` (the COMPILING
#   server's confdir, which differs when server and agent use different
#   layouts) only before that fact has been pluginsynced.
class greenbone (
  Sensitive[String]                       $password,
  Enum['unmanaged', 'docker']             $install_method  = 'unmanaged',
  Boolean                                 $manage_repo     = true,
  Pattern[/\Ahttps?:\/\/\S+\z/]           $repo_location   = 'https://dl.greenbone.net/repo/CE/stable',
  Pattern[/\Ahttps?:\/\/\S+\z/]           $repo_key_source = 'https://dl.greenbone.net/repo/CE/stable/greenbone-community-edition-keyring.gpg',
  Optional[String]                        $repo_key_id     = undef,
  Optional[String]                        $repo_release    = $facts.dig('os', 'distro', 'codename'),
  Hash[String, String]                    $packages        = {
    'gvmd'                => 'present',
    'gsad'                => 'present',
    'openvas-scanner'     => 'present',
    'ospd-openvas'        => 'present',
    'notus-scanner'       => 'present',
    'greenbone-feed-sync' => 'present',
    'pg-gvm'              => 'present',
  },
  Boolean                                 $manage_packages = true,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_user        = 'gvm',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group       = 'gvm',
  Pattern[/\A\//]                         $data_dir        = '/var/lib/gvm',
  Pattern[/\A\//]                         $log_dir         = '/var/log/gvm',
  Pattern[/\A\//]                         $run_dir         = '/run/gvm',
  Pattern[/\A\//]                         $feed_dir        = '/var/lib/gvm/feed',
  String[1]                               $user            = 'admin',
  Pattern[/\A\//]                         $socket          = '/run/gvmd/gvmd.sock',
  Pattern[/\A\//]                         $config_file     = "${$facts['greenbone_confdir'].lest || { $settings::confdir }}/gvm_transport.yaml",
) {
  if $install_method == 'unmanaged' {
    if $manage_repo {
      if !$repo_release {
        fail('greenbone: repo_release could not be determined from facts (os.distro.codename is absent); set greenbone::repo_release explicitly.')
      }
      $key_config = $repo_key_id ? {
        undef   => { 'source' => $repo_key_source },
        default => { 'id' => $repo_key_id, 'source' => $repo_key_source },
      }
      apt::source { 'greenbone-community-edition':
        location => $repo_location,
        release  => $repo_release,
        repos    => 'main',
        key      => $key_config,
        include  => {
          'src' => false,
          'deb' => true,
        },
      }
      Apt::Source['greenbone-community-edition'] -> Package<| tag == 'greenbone' |>
      Class['apt::update'] -> Package<| tag == 'greenbone' |>
    }

    if $manage_packages {
      $packages.each |String $pkg, String $ensure| {
        package { $pkg:
          ensure => $ensure,
          tag    => 'greenbone',
        }
      }
    }

    group { $gvm_group:
      ensure => present,
      system => true,
    }

    user { $gvm_user:
      ensure     => present,
      system     => true,
      gid        => $gvm_group,
      home       => $data_dir,
      shell      => '/usr/sbin/nologin',
      managehome => false,
      require    => Group[$gvm_group],
    }

    $dirs = [
      $data_dir,
      $log_dir,
      $run_dir,
      $feed_dir,
      "${data_dir}/scap-data",
      "${data_dir}/cert-data",
      "${data_dir}/gvmd",
      "${data_dir}/openvas",
      '/etc/gvm',
      '/etc/openvas',
      '/run/gvmd',
    ]

    $dirs.each |String $dir| {
      file { $dir:
        ensure  => directory,
        owner   => $gvm_user,
        group   => $gvm_group,
        mode    => '0750',
        require => User[$gvm_user],
      }
    }
  }

  file { $config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    # Pass the Sensitive password straight through; to_transport_yaml unwraps it
    # internally so the cleartext value is never exposed in the manifest scope.
    content => Sensitive(greenbone::to_transport_yaml(
        $user,
        $password,
        $socket,
    )),
  }
}
