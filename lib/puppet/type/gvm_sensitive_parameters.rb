# frozen_string_literal: true

# Propagates a Resource API `sensitive: true` schema flag onto the generated
# Puppet RAL attribute class, so Puppet redacts the value everywhere it reports.
#
# The schema flag alone does not do this. Resource API's
# TypeDefinition#create_attribute_in never declares `sensitive` on the class it
# generates, so the attribute's `sensitive` accessor stays nil and
# Puppet::Transaction::ResourceHarness#create_change_event takes its
# non-redacting branch. A declared secret then ships verbatim in the change
# notice, in the report event's desired_value (and from there to PuppetDB), and
# in the agent-local $statedir/last_run_report.yaml. Within the Resource API the
# flag only reaches validation error messages (type_definition.rb:244).
#
# Declaring it on the attribute class instead makes Puppet::Type's own
# set_sensitive_parameters pick it up via `is_sensitive`, which restores the
# built-in redaction: "changed [redacted] to [redacted]" in logs and
# `redacted => true` on the report event.
#
# A Sensitive()-wrapped manifest value is not a substitute. The Resource API
# re-wraps such values, so they happen to render as "Sensitive [value redacted]"
# through Ruby's to_s, but the event is still not flagged redacted -- and a
# plain String, which is what an unwrapped Hiera/eyaml lookup yields, leaks in
# full.
module Puppet::Type::GvmSensitiveParameters
  # attrclass is always present here: the Resource API creates one Puppet
  # parameter or property class per schema attribute, and every one of them
  # descends from Puppet::Parameter, which is where `sensitive` is defined.
  def self.register(type_name)
    type = Puppet::Type.type(type_name)

    type.type_definition.attributes.each do |name, options|
      type.attrclass(name).sensitive(true) if options[:sensitive] == true
    end
  end
end
