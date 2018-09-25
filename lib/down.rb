# frozen-string-literal: true

require "down/version"
require "down/net_http"

module Down
  module_function

  def download(*args, &block)
    backend.download(*args, &block)
  end

  def open(*args, &block)
    backend.open(*args, &block)
  end

  # Allows setting a backend via a symbol or a downloader object.
  def backend(value = nil)
    if value.is_a?(Symbol)
      require "down/#{value}"
      @backend = Down.const_get(value.to_s.split("_").map(&:capitalize).join)
    elsif value
      @backend = value
    else
      @backend
    end
  end
end

# Set Net::HTTP as the default backend
Down.backend Down::NetHttp
