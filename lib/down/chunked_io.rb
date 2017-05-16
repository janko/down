require "tempfile"
require "fiber"

module Down
  class ChunkedIO
    attr_accessor :size, :data

    def initialize(chunks:, size: nil, on_close: ->{}, data: {}, rewindable: true)
      @chunks   = chunks
      @size     = size
      @on_close = on_close
      @data     = data

      @buffer   = String.new
      @tempfile = Tempfile.new("down-chunked_io", binmode: true) if rewindable

      retrieve_chunk
    end

    def each_chunk
      raise IOError, "closed stream" if @closed

      return enum_for(__method__) if !block_given?
      yield retrieve_chunk until chunks_depleted?
    end

    def read(length = nil, outbuf = nil)
      raise IOError, "closed stream" if @closed

      outbuf = outbuf.to_s.replace("")

      @tempfile.read(length, outbuf) if @tempfile && !@tempfile.eof?

      until outbuf.bytesize == length || chunks_depleted?
        @buffer << retrieve_chunk if @buffer.empty?

        buffered_data = if length && length - outbuf.bytesize < @buffer.bytesize
                          @buffer.byteslice(0, length - outbuf.bytesize)
                        else
                          @buffer
                        end

        @tempfile.write(buffered_data) if @tempfile

        outbuf << buffered_data

        if buffered_data.bytesize < @buffer.bytesize
          @buffer.replace @buffer.byteslice(buffered_data.bytesize..-1)
        else
          @buffer.clear
        end
      end

      outbuf unless length && outbuf.empty?
    end

    def eof?
      raise IOError, "closed stream" if @closed

      return false if @tempfile && !@tempfile.eof?
      @buffer.empty? && chunks_depleted?
    end

    def rewind
      raise IOError, "closed stream" if @closed
      raise IOError, "this Down::ChunkedIO is not rewindable" if !@tempfile

      @tempfile.rewind
    end

    def close
      return if @closed

      chunks_fiber.resume(:terminate) if chunks_fiber.alive?
      @buffer.clear
      @tempfile.close! if @tempfile
      @closed = true
    end

    private

    def retrieve_chunk
      chunk = @next_chunk
      @next_chunk = chunks_fiber.resume
      chunk
    end

    def chunks_depleted?
      !chunks_fiber.alive?
    end

    def chunks_fiber
      @chunks_fiber ||= Fiber.new do
        begin
          @chunks.each do |chunk|
            action = Fiber.yield chunk
            break if action == :terminate
          end
        ensure
          @on_close.call
        end
      end
    end
  end
end
