# frozen-string-literal: true

require "down/version"
require "down/chunked_io"
require "down/errors"
require "down/utils"

require "fileutils"

module Down
  class Backend
    # Implemented by each backend.
    # @rbs!
    #   def download: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> downloaded_file?
    #   def open: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> ChunkedIO

    #: (url, *untyped, destination: String, **untyped) ?{ (untyped) -> untyped } -> nil
    #: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> downloaded_file
    def self.download(...)
      new.download(...)
    end

    #: (url, *untyped, **untyped) ?{ (untyped) -> untyped } -> ChunkedIO
    def self.open(...)
      new.open(...)
    end

    private

    # If destination path is defined, move tempfile to the destination,
    # otherwise return the tempfile unchanged.
    #: (Tempfile tempfile, String? destination) -> Tempfile?
    def download_result(tempfile, destination)
      return tempfile unless destination

      tempfile.close # required for Windows
      FileUtils.mv tempfile.path.to_s, destination

      nil
    end

    #: [V] (Enumerable[[String, V]] response_headers) -> Hash[String, V]
    def normalize_headers(response_headers)
      response_headers.to_h do |downcased_name, value|
        name = downcased_name.split("-").map(&:capitalize).join("-")
        [name, value]
      end
    end
  end
end
