# frozen-string-literal: true

require "down/version"
require "down/chunked_io"
require "down/errors"

require "fileutils"

module Down
  class Backend
    def self.download(*args, &block)
      new.download(*args, &block)
    end

    def self.open(*args, &block)
      new.open(*args, &block)
    end

    private

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
