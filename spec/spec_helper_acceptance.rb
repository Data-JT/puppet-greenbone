# frozen_string_literal: true

# Acceptance-test helper for puppet_litmus. These tests run against a real
# provisioned target, not in the unit-test process. Typical workflow:
#
#   bundle exec rake 'litmus:provision[docker, litmusimage/debian:12]'
#   bundle exec rake 'litmus:install_agent[puppet8]'
#   bundle exec rake litmus:install_module
#   bundle exec rake litmus:acceptance
#
require 'puppet_litmus'
require 'singleton'

class LitmusHelper
  include Singleton
  include PuppetLitmus
end

RSpec.configure do |c|
  c.include PuppetLitmus
  c.extend  PuppetLitmus
end
