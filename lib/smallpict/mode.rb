# frozen_string_literal: true

module SmallPict
  # Compression modes for `optimize(mode: ...)`. The server checks the mode
  # against the plan (403 mode_not_in_plan); the SDK does not.
  module Mode
    LOSSY    = "lossy"
    EXTREME  = "extreme"
    LOSSLESS = "lossless"
    ALL      = [LOSSY, EXTREME, LOSSLESS].freeze
  end
end
