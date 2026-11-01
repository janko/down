# frozen-string-literal: true

require "down/version"
require "down/net_http"

module Down
  # @rbs self.@backend: _Backend
  # @rbs @backend: _Backend
  module_function

  #: (url, *untyped, destination: String, **untyped) ?{ (untyped) -> untyped } -> nil
  #: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> downloaded_file
  def download(...)
    backend.download(...)
  end

  #: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> ChunkedIO
  def open(...)
    backend.open(...)
  end

  # Allows setting a backend via a symbol or a downloader object.
  #: (Symbol | _Backend) -> _Backend
  #: () -> _Backend
  def backend(value = nil)
    case value
    when Symbol
      require "down/#{value}"
      @backend = Down.const_get(value.to_s.split("_").map(&:capitalize).join)
    when nil
      @backend
    else
      @backend = value
    end
  end
end

# Set Net::HTTP as the default backend
Down.backend Down::NetHttp
