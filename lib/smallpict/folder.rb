# frozen_string_literal: true

module SmallPict
  # Light client-side check of an upload folder. The server is the authority
  # (400 invalid_folder): it lower-cases the value and enforces the full format.
  module Folder
    MAX_SEGMENTS = 3

    def self.validate!(folder)
      segments = folder.to_s.split("/", -1)
      if segments.empty? || segments.any?(&:empty?) || segments.include?("..") || segments.size > MAX_SEGMENTS
        raise ValidationError, "Invalid folder #{folder.inspect}: use 1-#{MAX_SEGMENTS} non-empty segments separated by '/', without '..'."
      end

      folder.to_s
    end
  end
end
