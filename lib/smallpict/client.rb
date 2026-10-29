# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module SmallPict
  class Client
    attr_reader :api_key, :secret_key, :base_url, :timeout, :max_retries, :fallback_mode

    def initialize(
      api_key: nil,
      secret_key: nil,
      base_url: nil,
      timeout: nil,
      max_retries: nil,
      fallback_mode: nil
    )
      config = SmallPict.configuration

      @api_key       = api_key || config.api_key
      @secret_key    = secret_key || config.secret_key
      @base_url      = (base_url || config.base_url).chomp("/")
      @timeout       = (timeout || config.timeout).to_i
      @max_retries   = (max_retries || config.max_retries).to_i
      @fallback_mode = (fallback_mode || config.fallback_mode).to_sym

      validate_configuration!
    end

    def optimize(source, options = {})
      opts = options.is_a?(Models::OptimizeOptions) ? options : Models::OptimizeOptions.new(**options)
      resolved = resolve_source(source, opts)

      payload = {
        filename:     resolved[:filename],
        mime_type:    resolved[:mime_type],
        content_type: resolved[:mime_type],
        filesize:     resolved[:filesize],
        options:      opts.to_h
      }

      begin
        res = request(:post, "/v1/optimize", payload, idempotency_key: opts.idempotency_key)
        Models::OptimizeResult.new(res)
      rescue QuotaExceededError => e
        if @fallback_mode == :passthrough
          format_str = resolved[:mime_type].to_s.sub("image/", "")
          Models::OptimizeResult.new(
            job_id:             "fallback-passthrough",
            status:             "completed",
            url:                "",
            format:             format_str,
            original_size:      resolved[:filesize],
            compressed_size:    resolved[:filesize],
            bytes_saved:        0,
            savings_percentage: 0.0,
            data:               resolved[:bytes]
          )
        else
          raise e
        end
      end
    end

    def get_quota
      res = request(:get, "/v1/quota")
      Models::QuotaResponse.new(res)
    end

    # purge_type: "url" (default), "folder" (with `folder:`) or "all".
    def purge_cdn(urls = [], purge_type: "url", folder: nil)
      url_list = urls.is_a?(Array) ? urls : [urls]
      payload = {
        purge_type: purge_type.to_s,
        urls:       url_list
      }
      if payload[:purge_type] == "folder"
        raise ValidationError, "folder is required for purge_type \"folder\"" if folder.nil? || folder.to_s.empty?

        payload[:folder] = Folder.validate!(folder)
      end

      res = request(:post, "/v1/purge", payload)
      Models::PurgeResponse.new(res)
    end

    def validate_key
      get_quota
      true
    rescue StandardError
      false
    end

    def get_job_status(job_id)
      raise ValidationError, "job_id is required" if job_id.nil? || job_id.to_s.empty?

      res = request(:get, "/v1/optimize/status?job_id=#{job_id}")
      Models::JobStatusResult.new(res)
    end

    private

    def validate_configuration!
      if @api_key.nil? || @api_key.to_s.strip.empty?
        raise ValidationError, "Missing required SmallPict API key. Provide `api_key:` or configure via `SmallPict.configure`."
      end
    end

    def request(method, path, body = nil, idempotency_key: nil)
      clean_path = path.start_with?("/") ? path : "/#{path}"
      clean_path = "/v1#{clean_path}" unless clean_path.start_with?("/v1/") || clean_path.start_with?("/v2/")

      url = "#{@base_url}#{clean_path}"
      body_str = body ? JSON.generate(body) : nil
      body_hash = body_str ? Crypto.sha256_hex(body_str) : Crypto::EMPTY_SHA256

      attempt = 0
      base_delay = 0.25 # 250ms

      while attempt <= @max_retries
        attempt += 1
        begin
          timestamp = Time.now.to_i.to_s

          headers = {
            "Accept"     => "application/json",
            "X-API-Key"  => @api_key
          }
          headers["Content-Type"] = "application/json" if body_str

          if @secret_key
            string_to_sign = Crypto.build_string_to_sign(method, clean_path, timestamp, body_hash)
            signature = Crypto.hmac_sha256_hex(@secret_key, string_to_sign)
            headers["X-Timestamp"] = timestamp
            headers["X-Signature"] = signature
          else
            headers["Authorization"] = "Bearer #{@api_key}"
          end

          if %i[post patch delete].include?(method.to_s.downcase.to_sym)
            headers["Idempotency-Key"] = idempotency_key || SecureRandom.uuid
          end

          response = connection.send(method.to_s.downcase.to_sym, url) do |req|
            req.headers = headers
            req.body = body_str if body_str
          end

          status = response.status
          request_id = response.headers["x-request-id"]
          retry_after = response.headers["retry-after"]&.to_i

          if (status == 429 && !hourly_purge_limit?(response.body)) || (status >= 500 && status <= 504)
            if attempt <= @max_retries
              delay = base_delay * (2**(attempt - 1))
              delay = retry_after if retry_after && retry_after.positive?
              jitter = rand(0..100) / 1000.0
              sleep(delay + jitter)
              next
            end
          end

          parsed = parse_body(response.body)

          if status < 200 || status >= 300
            handle_error_response(status, parsed, request_id, retry_after)
          end

          return parsed
        rescue Faraday::TimeoutError => e
          raise TimeoutError, e.message
        rescue Faraday::ConnectionFailed => e
          if attempt <= @max_retries
            sleep(base_delay * (2**(attempt - 1)))
            next
          end
          raise NetworkError, e.message
        end
      end

      raise TimeoutError, "Request failed after maximum retry attempts"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout = @timeout
        f.options.open_timeout = @timeout
        f.adapter Faraday.default_adapter
      end
    end

    # 429 purge_rate_limited is an hourly limit: retrying within seconds cannot succeed.
    def hourly_purge_limit?(body_str)
      body = parse_body(body_str)
      body.is_a?(Hash) && body["error"].is_a?(Hash) && body["error"]["code"] == "purge_rate_limited"
    end

    def parse_body(body_str)
      return {} if body_str.nil? || body_str.empty?

      JSON.parse(body_str)
    rescue JSON::ParserError
      { "raw" => body_str }
    end

    def handle_error_response(status, body, request_id, retry_after)
      message = "API request failed with HTTP #{status}"
      details = nil

      if body.is_a?(Hash)
        if body["error"].is_a?(Hash)
          message = body["error"]["message"] || message
          details = body["error"]["details"]
        elsif body["error"].is_a?(String)
          message = body["error"]
        elsif body["message"].is_a?(String)
          message = body["message"]
        end
      end

      case status
      when 400 then raise ValidationError.new(message, request_id: request_id, details: details)
      when 401 then raise AuthenticationError.new(message, request_id: request_id, details: details)
      when 402 then raise QuotaExceededError.new(message, request_id: request_id, details: details)
      when 403 then raise PermissionDeniedError.new(message, request_id: request_id, details: details)
      when 404 then raise NotFoundError.new(message, request_id: request_id, details: details)
      when 429 then raise RateLimitError.new(message, retry_after: retry_after, request_id: request_id, details: details)
      else
        if status >= 500
          raise ServerError.new(message, status_code: status, request_id: request_id, details: details)
        end

        raise Error.new(message, status_code: status, request_id: request_id, details: details)
      end
    end

    def resolve_source(source, options)
      filename = options.filename || "image.jpg"
      mime_type = options.mime_type || (options.respond_to?(:content_type) ? options.content_type : nil) || "image/jpeg"
      filesize = 0
      bytes = nil

      if source.respond_to?(:read)
        bytes = source.read
        filesize = bytes.bytesize
        filename = File.basename(source.path) if source.respond_to?(:path) && options.filename.nil?
      elsif source.is_a?(String)
        if File.exist?(source) && File.file?(source)
          filename = File.basename(source) if options.filename.nil?
          bytes = File.binread(source)
          filesize = bytes.bytesize
        else
          # Raw binary data
          bytes = source
          filesize = bytes.bytesize
        end
      end

      {
        filename:  filename,
        mime_type: mime_type,
        filesize:  filesize,
        bytes:     bytes
      }
    end
  end
end
