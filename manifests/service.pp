# @summary Manages the Greenbone service ensemble.
#
# Controls ospd-openvas, notus-scanner, openvasd, gvmd, and gsad.
# Start order matters: ospd-openvas and notus-scanner must be running
# before gvmd starts, and gvmd must be running before gsad.
#
# @param ensure
#   Desired state for all services (running/stopped).
# @param enable
#   Whether to enable services at boot.
# @param services
#   Override the set of managed services and their ordering constraints.
#   Keys are service names; value is a hash with optional 'require' list.
class greenbone::service (
  Enum['running', 'stopped'] $ensure = 'running',
  Boolean                    $enable = true,
  # Default service dependency chain. Each value lists prerequisite services.
  Hash[String, Hash]         $services = {
    'notus-scanner' => { require => [] },
    'ospd-openvas'  => { require => ['notus-scanner'] },
    'openvasd'      => { require => [] },
    'gvmd'          => { require => ['ospd-openvas', 'openvasd'] },
    'gsad'          => { require => ['gvmd'] },
  },
) {
  $services.each |String $svc, Hash $cfg| {
    $prereqs = ($cfg['require'] =~ Array) ? {
      true    => $cfg['require'],
      default => [],
    }
    $prereqs.each |String $dep| {
      unless $dep in $services {
        fail("greenbone::service: '${svc}' requires '${dep}', which is not in the managed services set")
      }
    }
    $prereq_refs = $prereqs.map |String $dep| { Service[$dep] }

    service { $svc:
      ensure  => $ensure,
      enable  => $enable,
      require => $prereq_refs,
    }
  }
}
