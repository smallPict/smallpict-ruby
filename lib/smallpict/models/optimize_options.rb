# frozen_string_literal: true

module SmallPict
  module Models
    class OptimizeOptions
      attr_reader :format, :quality, :max_width, :max_height, :max_dimension, :fit,
                  :mode, :lossless, :folder, :strip_metadata, :filename, :mime_type, :content_type, :idempotency_key

      # mode:     SmallPict::Mode::LOSSY (server default when omitted), EXTREME or LOSSLESS.
      # quality:  optional 1-100; omitted when nil so the server picks the default per mode.
      # folder:   optional upload folder, e.g. "products/shoes"; the server lower-cases it.
      # lossless: deprecated, use `mode: SmallPict::Mode::LOSSLESS`; removal not before the next major.
      def initialize(
        format: "auto",
        quality: nil,
        max_width: nil,
        max_height: nil,
        max_dimension: nil,
        fit: "cover",
        mode: nil,
        lossless: nil,
        folder: nil,
        strip_metadata: true,
        filename: nil,
        mime_type: nil,
        content_type: nil,
        idempotency_key: nil
      )
        @format          = format.to_s
        @quality         = quality&.clamp(1, 100)
        @max_width       = max_width
        @max_height      = max_height
        @max_dimension   = max_dimension
        @fit             = fit.to_s
        @lossless        = lossless
        @mode            = resolve_mode(mode, lossless)
        @folder          = folder.nil? ? nil : Folder.validate!(folder)
        @strip_metadata  = strip_metadata
        @filename        = filename
        @mime_type       = mime_type || content_type
        @content_type    = content_type || mime_type
        @idempotency_key = idempotency_key
      end

      def to_h
        {
          format: @format,
          quality: @quality,
          max_width: @max_width,
          max_height: @max_height,
          max_dimension: @max_dimension,
          fit: @fit,
          mode: @mode,
          folder: @folder,
          strip_metadata: @strip_metadata
        }.compact
      end

      private

      # `lossless:` is deprecated: map it to `mode:` and never send it on the wire.
      def resolve_mode(mode, lossless)
        mode = mode&.to_s
        unless lossless.nil?
          Kernel.warn("SmallPict: `lossless:` is deprecated, use `mode: SmallPict::Mode::LOSSLESS`.",
                      category: :deprecated)
        end
        return mode unless lossless == true
        return Mode::LOSSLESS if mode.nil? || mode == Mode::LOSSLESS

        raise ValidationError, "`lossless: true` contradicts `mode: #{mode.inspect}`; set only `mode:`."
      end
    end
  end
end
