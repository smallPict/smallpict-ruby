# frozen_string_literal: true

module SmallPict
  module Models
    class JobStatusResult
      attr_reader :job_id, :status, :url, :format, :bytes_saved,
                  :error, :created_at, :updated_at, :mode_applied, :quality_applied, :folder

      def initialize(attributes = {})
        @job_id      = attributes[:job_id] || attributes["job_id"]
        @status      = attributes[:status] || attributes["status"] || "processing"
        @url         = attributes[:url] || attributes["url"]
        @format      = attributes[:format] || attributes["format"]
        @bytes_saved = attributes[:bytes_saved] || attributes["bytes_saved"]
        @error       = attributes[:error] || attributes["error"]
        @created_at  = attributes[:created_at] || attributes["created_at"]
        @updated_at  = attributes[:updated_at] || attributes["updated_at"]
        # Reported by the server; nil for jobs created before modes existed.
        @mode_applied    = attributes[:mode_applied] || attributes["mode_applied"]
        @quality_applied = attributes[:quality_applied] || attributes["quality_applied"]
        @folder          = attributes[:folder] || attributes["folder"]
      end
    end
  end
end
