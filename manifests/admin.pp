# @summary Creates the initial GVM admin user.
#
# Uses the gvm_admin custom type, which calls gvmd CLI via array-based
# execution (no shell). The password is marked Sensitive and never appears as
# plaintext in the compiled catalog, reports, or logs.
#
# Note: gvmd requires --password as a CLI argument; the value therefore appears
# in the process argv during the creation run. Rotate the bootstrap password
# after initial provisioning.
#
# Must run after gvmd is started and gvmd --migrate has completed.
#
# @param username
#   GVM username to create.
# @param password
#   Password for the admin user. Wrapped in Sensitive.
# @param gvm_user
#   System user that runs gvmd commands.
# @param gvm_group
#   System group for gvmd.
# @param gvmd_bin
#   Path to the gvmd binary.
class greenbone::admin (
  Sensitive[String]                       $password,
  String[1]                               $username  = 'admin',
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_user  = $greenbone::gvm_user,
  Pattern[/\A[A-Za-z_][A-Za-z0-9_\-]*\z/] $gvm_group = $greenbone::gvm_group,
  Pattern[/\A\//]                         $gvmd_bin  = '/usr/sbin/gvmd',
) {
  gvm_admin { $username:
    ensure    => present,
    password  => $password,
    gvmd_bin  => $gvmd_bin,
    gvm_user  => $gvm_user,
    gvm_group => $gvm_group,
    require   => [
      Exec['gvmd-migrate'],
      Service['gvmd'],
    ],
  }
}
