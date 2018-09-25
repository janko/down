# frozen-string-literal: true

require "down/version"
require "down/chunked_io"
require "down/errors"
require "down/utils"

require "fileutils"
require "addressable/uri"

module Down
  class Backend
    def self.download(*args, &block)
      new.download(*args, &block)
    end

    def self.open(*args, &block)
      new.open(*args, &block)
    end

    private

    def normalize(url)
      uri = Addressable::URI.parse(url).normalize
      raise if uri.host.nil?
      uri.to_s
    rescue
      raise Down::InvalidUrl
    end

    def download_result(tempfile, destination)
      if destination
        tempfile.close
        FileUtils.mv tempfile.path, destination
        nil
      else
        tempfile
      end
    end
  end
end
