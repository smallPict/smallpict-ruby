# frozen_string_literal: true

require "smallpict"
require "webmock/rspec"
require "tempfile"
require "pathname"
require "stringio"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random

  config.before(:each) do
    SmallPict.reset_configuration!
  end
end
