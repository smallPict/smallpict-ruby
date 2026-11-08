# frozen_string_literal: true

module SmallPict
  class Error < StandardError
    # upgrade_url: dashboard page where the missing capacity is added
    # (details.upgrade_url), or nil. The SDK never opens or fetches it.
    attr_reader :code, :status_code, :request_id, :details, :upgrade_url

    def initialize(message = "", code: "INTERNAL_ERROR", status_code: nil, request_id: nil, details: nil)
      @raw_message = self.class.sanitize(message)
      @code        = code
      @status_code = status_code
      @request_id  = request_id
      @details     = details
      url          = details.is_a?(Hash) ? (details["upgrade_url"] || details[:upgrade_url]) : nil
      @upgrade_url = url.is_a?(String) ? url : nil
      super(@raw_message)
    end

    def to_s
      status_str = @status_code ? " HTTP #{@status_code}" : ""
      req_str = @request_id ? " (Request ID: #{@request_id})" : ""
      "[#{@code}#{status_str}]: #{@raw_message}#{req_str}"
    end

    def inspect
      "#<#{self.class.name} code=#{@code.inspect} status_code=#{@status_code.inspect} message=#{@raw_message.inspect}>"
    end

    def self.sanitize(msg)
      return "" if msg.nil? || msg.empty?

      sanitized = msg.to_s.gsub(/sp_(test|sdk|wp)_[a-zA-Z0-9_-]{10,}/) do |match|
        if match.length > 14
          "#{match[0..9]}...#{match[-4..]}"
        else
          "#{match[0..5]}..."
        end
      end

      # Server-issued secrets are "sps_" + hex; sec_/secret_ are the test fixtures.
      sanitized = sanitized.gsub(/(sps_[a-f0-9]{16,}|(sec|secret)_[a-zA-Z0-9_-]{8,})/i, "***REDACTED***")
      sanitized.gsub(/Bearer\s+[a-zA-Z0-9._-]+/i, "Bearer ***REDACTED***")
    end
  end

  class ValidationError < Error
    def initialize(message = "Validation failed", request_id: nil, details: nil)
      super(message, code: "VALIDATION_FAILED", status_code: 400, request_id: request_id, details: details)
    end
  end

  class AuthenticationError < Error
    def initialize(message = "Authentication failed", request_id: nil, details: nil)
      super(message, code: "UNAUTHORIZED", status_code: 401, request_id: request_id, details: details)
    end
  end

  class QuotaExceededError < Error
    def initialize(message = "Storage or optimization quota exceeded", request_id: nil, details: nil)
      super(message, code: "QUOTA_EXCEEDED", status_code: 402, request_id: request_id, details: details)
    end
  end

  class PermissionDeniedError < Error
    # Modes the plan allows, from details.allowed_modes of 403 mode_not_in_plan; otherwise nil.
    attr_reader :allowed_modes

    def initialize(message = "Permission denied for this resource", request_id: nil, details: nil)
      super(message, code: "FORBIDDEN", status_code: 403, request_id: request_id, details: details)
      modes = details.is_a?(Hash) ? (details["allowed_modes"] || details[:allowed_modes]) : nil
      @allowed_modes = modes.is_a?(Array) ? modes.grep(String) : nil
    end
  end

  class NotFoundError < Error
    def initialize(message = "Resource or job ID not found", request_id: nil, details: nil)
      super(message, code: "NOT_FOUND", status_code: 404, request_id: request_id, details: details)
    end
  end

  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = "Rate limit exceeded", retry_after: nil, request_id: nil, details: nil)
      super(message, code: "RATE_LIMIT_EXCEEDED", status_code: 429, request_id: request_id, details: details)
      @retry_after = retry_after
    end
  end

  class ServerError < Error
    def initialize(message = "Internal server error occurred", status_code: 500, request_id: nil, details: nil)
      super(message, code: "INTERNAL_ERROR", status_code: status_code, request_id: request_id, details: details)
    end
  end

  class TimeoutError < Error
    def initialize(message = "Request timed out after maximum duration", request_id: nil, details: nil)
      super(message, code: "TIMEOUT_ERROR", status_code: 408, request_id: request_id, details: details)
    end
  end

  class NetworkError < Error
    def initialize(message = "Network communication error", details: nil)
      super(message, code: "NETWORK_ERROR", status_code: nil, request_id: nil, details: details)
    end
  end
end
