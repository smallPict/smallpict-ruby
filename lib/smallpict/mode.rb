# frozen_string_literal: true

module SmallPict
  # Compression modes for `optimize(mode: ...)`. The server checks the mode
  # against the plan (403 mode_not_in_plan); the SDK does not.
  module Mode
    LOSSY    = "lossy"
    EXTREME  = "extreme"
    LOSSLESS = "lossless"
    AUTO     = "auto" # the server picks the quality per image from a visual score (CMP-07)
    ALL      = [LOSSY, EXTREME, LOSSLESS, AUTO].freeze
  end
end
