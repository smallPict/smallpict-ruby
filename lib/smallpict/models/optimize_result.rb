# frozen_string_literal: true

module SmallPict
  module Models
    class OptimizeResult
      attr_reader :job_id, :status, :url, :format, :original_size,
                  :compressed_size, :bytes_saved, :savings_percentage,
                  :upload_url, :data, :folder

      def initialize(attributes = {})
        @job_id             = attributes[:job_id] || attributes["job_id"] || "sync"
        @status             = attributes[:status] || attributes["status"] || "completed"
        @url                = attributes[:url] || attributes["url"] || ""
        @format             = attributes[:format] || attributes["format"] || "auto"
        @original_size      = (attributes[:original_size] || attributes["original_size"] || 0).to_i
        @compressed_size    = (attributes[:compressed_size] || attributes["compressed_size"] || @original_size).to_i
        @bytes_saved        = (attributes[:bytes_saved] || attributes["bytes_saved"] || [@original_size - @compressed_size, 0].max).to_i
        @savings_percentage = (attributes[:savings_percentage] || attributes["savings_percentage"] || calculate_savings_percentage).to_f.round(2)
        @upload_url         = attributes[:upload_url] || attributes["upload_url"]
        @data               = attributes[:data]
        # Normalized (lower case) by the server; nil without a folder.
        @folder             = attributes[:folder] || attributes["folder"]
      end

      private

      def calculate_savings_percentage
        return 0.0 if @original_size.zero?

        ((@bytes_saved.to_f / @original_size) * 100.0).round(2)
      end
    end
  end
end
