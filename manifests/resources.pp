# @summary Declares GVM API resources from Hiera data.
#
# Include this class after the main `greenbone` class when you prefer
# data-driven resource declarations over inline gvm_* resource blocks.
#
# @param schedules
#   Hash of gvm_schedule resources, keyed by schedule name.
# @param targets
#   Hash of gvm_target resources, keyed by target name.
# @param tasks
#   Hash of gvm_task resources, keyed by task name.
# @param users
#   Hash of gvm_user resources, keyed by username.
# @param user_settings
#   Hash of gvm_user_setting resources, keyed as 'setting_name'. One naming a
#   filter from `filters` as its filter_name is ordered after it.
# @param filters
#   Hash of gvm_filter resources, keyed by filter name.
# @param groups
#   Hash of gvm_group resources, keyed by group name. Ordered after every
#   gvm_user, since members are referenced by name.
# @param permissions
#   Hash of gvm_permission resources, keyed by a Puppet-side name stored as a
#   marker in the permission comment (see the gvm_permission type docs).
#   Ordered after every gvm_user and gvm_group, which they name.
# @param scan_configs
#   Hash of gvm_scan_config resources, keyed by config name. A task naming one
#   of them as its config_name is ordered after it.
# @param overrides
#   Hash of gvm_override resources, keyed by a Puppet-side name. A GVM override
#   has no name of its own, so that key is stored as a marker inside the
#   override text -- see the gvm_override type docs before choosing one, and
#   treat it as immutable once applied.
#
# @example Hiera data
#   greenbone::resources::schedules:
#     weekly-monday-0200:
#       icalendar: "BEGIN:VCALENDAR\nVERSION:2.0\n..."
#       timezone: Europe/Berlin
#   greenbone::resources::targets:
#     internal-network:
#       hosts: '192.0.2.0/24'
#       port_list_name: 'All IANA assigned TCP'
#   greenbone::resources::tasks:
#     weekly-internal:
#       target_name: internal-network
#       config_name: 'Full and fast'
#       schedule_name: weekly-monday-0200
#   greenbone::resources::scan_configs:
#     'Full and fast (tuned)':
#       base_config: 'Full and fast'
#       scanner_preferences:
#         expand_vhosts: '0'
#   greenbone::resources::filters:
#     'Results (overrides applied)':
#       term: 'apply_overrides=1 levels=chml rows=100 min_qod=70 first=1 sort-reverse=severity'
#   greenbone::resources::user_settings:
#     'Results Filter':
#       filter_name: 'Results (overrides applied)'
#       setting_id: '739ab810-163d-11e3-9af6-406186ea4fc5'
#   greenbone::resources::groups:
#     'Shared by admin':
#       users: ['admin']
#   greenbone::resources::permissions:
#     alice-super-on-admin:
#       permission: 'Super'
#       subject_type: 'user'
#       subject_name: 'alice'
#       resource_type: 'group'
#       resource_name: 'Shared by admin'
#   greenbone::resources::overrides:
#     tcp-timestamps-false-positive:
#       nvt_oid: '1.3.6.1.4.1.25623.1.0.80091'
#       new_severity: -1
#       text: 'Assessed false positive: kernel randomises per-connection TCP timestamp offsets.'
class greenbone::resources (
  Hash[String, Hash] $schedules    = {},
  Hash[String, Hash] $targets      = {},
  Hash[String, Hash] $tasks        = {},
  Hash[String, Hash] $users        = {},
  Hash[String, Hash] $user_settings = {},
  Hash[String, Hash] $overrides    = {},
  Hash[String, Hash] $scan_configs = {},
  Hash[String, Hash] $filters      = {},
  Hash[String, Hash] $groups       = {},
  Hash[String, Hash] $permissions  = {},
) {
  $schedules.each |String $title, Hash $attributes| {
    gvm_schedule { $title:
      * => $attributes,
    }
  }

  $targets.each |String $title, Hash $attributes| {
    gvm_target { $title:
      * => $attributes,
    }
  }

  $scan_configs.each |String $title, Hash $attributes| {
    gvm_scan_config { $title:
      * => $attributes,
    }
  }

  $tasks.each |String $title, Hash $attributes| {
    gvm_task { $title:
      * => $attributes,
    }
  }

  $users.each |String $title, Hash $attributes| {
    gvm_user { $title:
      * => $attributes,
    }
  }

  $groups.each |String $title, Hash $attributes| {
    gvm_group { $title:
      * => $attributes,
    }
  }

  $permissions.each |String $title, Hash $attributes| {
    gvm_permission { $title:
      * => $attributes,
    }
  }

  # Groups name users as members and permissions name users and groups, all by
  # name, resolved at write time -- so each must exist first.
  Gvm_user <| |> -> Gvm_group <| |>
  Gvm_user <| |> -> Gvm_permission <| |>
  Gvm_group <| |> -> Gvm_permission <| |>

  $filters.each |String $title, Hash $attributes| {
    gvm_filter { $title:
      * => $attributes,
    }
  }

  $user_settings.each |String $title, Hash $attributes| {
    gvm_user_setting { $title:
      * => $attributes,
    }
    $filter = $attributes['filter_name']
    if $filter and $filter in $filters {
      Gvm_filter[$filter] -> Gvm_user_setting[$title]
    }
  }

  # Overrides reference an NVT by OID, not by any object managed here, so they
  # need none of the ordering the tasks below do.
  $overrides.each |String $title, Hash $attributes| {
    gvm_override { $title:
      * => $attributes,
    }
  }

  # Tasks depend on their referenced target, schedule and config when declared here
  $tasks.each |String $task_name, Hash $task_attrs| {
    $target = $task_attrs['target_name']
    if $target and $target in $targets {
      Gvm_target[$target] -> Gvm_task[$task_name]
    }
    $schedule = $task_attrs['schedule_name']
    if $schedule and $schedule in $schedules {
      Gvm_schedule[$schedule] -> Gvm_task[$task_name]
    }
    $config = $task_attrs['config_name']
    if $config and $config in $scan_configs {
      Gvm_scan_config[$config] -> Gvm_task[$task_name]
    }
  }
}
