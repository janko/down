# frozen-string-literal: true

require "down/version"
require "down/chunked_io"
require "down/errors"

module Down
  class Backend
    def self.download(*args, &block)
      new.download(*args, &block)
    end

    def self.open(*args, &block)
      new.open(*args, &block)
    end
  end
end
