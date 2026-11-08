# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module SmallPict
  class Client
    attr_reader :api_key, :secret_key, :base_url, :timeout, :max_retries, :fallback_mode,
                :poll_interval, :wait_timeout

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end
    alias to_s inspect

    def initialize(
      api_key: nil,
      secret_key: nil,
      base_url: nil,
      timeout: nil,
      max_retries: nil,
      fallback_mode: nil,
      poll_interval: nil,
      wait_timeout: nil
    )
      config = SmallPict.configuration

      @api_key       = api_key || config.api_key
      @secret_key    = secret_key || config.secret_key
      @base_url      = (base_url || config.base_url).chomp("/")
      @timeout       = (timeout || config.timeout).to_i
      @max_retries   = (max_retries || config.max_retries).to_i
      @fallback_mode = (fallback_mode || config.fallback_mode).to_sym
      @poll_interval = poll_interval || config.poll_interval
      @wait_timeout  = wait_timeout || config.wait_timeout

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
        queued = request(:post, "/v1/optimize", payload, idempotency_key: opts.idempotency_key)
      rescue QuotaExceededError => e
        if @fallback_mode == :passthrough
          format_str = resolved[:mime_type].to_s.sub("image/", "")
          return Models::OptimizeResult.new(
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

      # The worker waits 30 s from the request for the object: upload now, poll after.
      upload(queued["upload_url"], resolved[:bytes], resolved[:mime_type])
      wait_for_job(queued["job_id"], resolved[:filesize])
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

    # PUT the bytes to the pre-signed URL with only the two headers it was signed for:
    # S3 refuses API headers or another type or length with 403. No retry: the worker
    # stops waiting for the object 30 s after the job was queued.
    def upload(url, bytes, mime_type)
      response = connection.put(url) do |req|
        req.headers = { "Content-Type" => mime_type, "Content-Length" => bytes.bytesize.to_s }
        req.body = bytes
      end
      return if response.status >= 200 && response.status < 300

      text = response.body.to_s
      message = "Upload to staging failed with HTTP #{response.status}#{text.empty? ? "" : ": #{text}"}"
      raise Error.new(message, code: "upload_failed", status_code: response.status)
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Upload to staging timed out: #{e.message}"
    rescue Faraday::Error => e
      raise NetworkError, e.message
    end

    def wait_for_job(job_id, original_size)
      deadline = monotonic_now + @wait_timeout
      loop do
        sleep([@poll_interval, [deadline - monotonic_now, 0].max].min)
        status = get_job_status(job_id)

        case status.status
        when "completed"
          bytes_saved = status.bytes_saved.to_i
          return Models::OptimizeResult.new(
            job_id:          status.job_id || job_id,
            status:          "completed",
            url:             status.url || "",
            format:          status.format || "",
            original_size:   original_size,
            compressed_size: original_size - bytes_saved,
            bytes_saved:     bytes_saved,
            mode_applied:    status.mode_applied,
            quality_applied: status.quality_applied,
            folder:          status.folder
          )
        when "failed"
          err = status.error
          message = err.is_a?(Hash) ? err["message"] : err
          message = "The optimization job failed." if message.nil? || message.to_s.empty?
          raise Error.new(message.to_s, code: "job_failed", details: { "job_id" => job_id })
        end

        if monotonic_now >= deadline
          raise TimeoutError,
                "Job #{job_id} did not finish within #{@wait_timeout}s; poll get_job_status(\"#{job_id}\") later."
        end
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

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

      idempotency_key ||= SecureRandom.uuid
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

          # The server rejects a repeated signature as a replay unless the nonce differs.
          headers["X-Nonce"] = SecureRandom.uuid
          if %i[post patch delete].include?(method.to_s.downcase.to_sym)
            headers["Idempotency-Key"] = idempotency_key
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
      code = "INTERNAL_ERROR"

      if body.is_a?(Hash)
        if body["error"].is_a?(Hash)
          message = body["error"]["message"] || message
          details = body["error"]["details"]
          code = body["error"]["code"] if body["error"]["code"].is_a?(String)
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

        raise Error.new(message, code: code, status_code: status, request_id: request_id, details: details)
      end
    end

    def resolve_source(source, options)
      filename = options.filename || "image.jpg"
      mime_type = options.mime_type || (options.respond_to?(:content_type) ? options.content_type : nil) || "image/jpeg"
      filesize = 0
      bytes = nil

      if source.is_a?(String) && source.start_with?("http://", "https://")
        raise ValidationError, "the API does not fetch URLs; download the image and pass its bytes"
      end

      if source.respond_to?(:read)
        bytes = source.read
        filesize = bytes.bytesize
        path = source.respond_to?(:to_path) ? source.to_path : (source.path if source.respond_to?(:path))
        filename = File.basename(path) if path && options.filename.nil?
      elsif source.is_a?(String)
        # Image bytes hold NUL, which File.file? refuses with ArgumentError; only probe a plausible path.
        if !source.include?("\0") && File.file?(source)
          filename = File.basename(source) if options.filename.nil?
          bytes = File.binread(source)
          filesize = bytes.bytesize
        else
          # Raw binary data
          bytes = source
          filesize = bytes.bytesize
        end
      else
        raise ValidationError, "Unsupported image source: pass an IO, a file path or the image bytes as a String"
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
