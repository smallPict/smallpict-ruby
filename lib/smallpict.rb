# frozen_string_literal: true

require_relative "smallpict/version"
require_relative "smallpict/configuration"
require_relative "smallpict/crypto"
require_relative "smallpict/errors"
require_relative "smallpict/mode"
require_relative "smallpict/folder"
require_relative "smallpict/models/optimize_options"
require_relative "smallpict/models/optimize_result"
require_relative "smallpict/models/capacity"
require_relative "smallpict/models/quota_response"
require_relative "smallpict/models/purge_response"
require_relative "smallpict/models/job_status_result"
require_relative "smallpict/client"
require_relative "smallpict/active_storage/service"

module SmallPict
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
      @default_client = nil
    end

    def client
      @default_client ||= Client.new
    end

    def optimize(source, options = {})
      client.optimize(source, options)
    end

    def get_quota
      client.get_quota
    end

    def purge_cdn(urls = [], purge_type: "url", folder: nil)
      client.purge_cdn(urls, purge_type: purge_type, folder: folder)
    end

    def validate_key
      client.validate_key
    end

    def get_job_status(job_id)
      client.get_job_status(job_id)
    end
  end
end
