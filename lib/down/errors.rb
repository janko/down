module Down
  class Error < StandardError
  end

  class TooLarge < Error
  end

  class NotFound < Error
    attr_reader :response

    def initialize(message, response: nil)
      super(message)
      @response = response
    end
  end
end
