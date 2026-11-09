# frozen_string_literal: true

module SmallPict
  class Configuration
    attr_accessor :api_key, :secret_key, :base_url, :timeout, :max_retries, :fallback_mode,
                  :poll_interval, :wait_timeout

    def initialize
      @api_key       = ENV.fetch("SMALLPICT_API_KEY", nil)
      @secret_key    = ENV.fetch("SMALLPICT_SECRET_KEY", nil)
      @base_url      = (ENV["SMALLPICT_BASE_URL"] || "https://api.smallpict.app").chomp("/")
      @timeout       = 30
      @max_retries   = 3
      @fallback_mode = :throw
      @poll_interval = 1   # seconds between job status polls in optimize
      @wait_timeout  = 120 # seconds optimize waits for the job before TimeoutError
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end
    alias to_s inspect
  end
end
