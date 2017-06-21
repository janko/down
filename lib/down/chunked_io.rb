# frozen-string-literal: true

require "tempfile"
require "fiber"

module Down
  class ChunkedIO
    attr_accessor :size, :data, :encoding

    def initialize(chunks:, size: nil, on_close: nil, data: {}, rewindable: true, encoding: nil)
      @chunks     = chunks
      @size       = size
      @on_close   = on_close
      @data       = data
      @encoding   = find_encoding(encoding || Encoding::BINARY)
      @rewindable = rewindable
      @buffer     = nil

      retrieve_chunk
    end

    def each_chunk
      raise IOError, "closed stream" if closed?

      return enum_for(__method__) if !block_given?
      yield retrieve_chunk until chunks_depleted?
    end

    def read(length = nil, outbuf = nil)
      raise IOError, "closed stream" if closed?

      outbuf = outbuf.to_s.replace("").force_encoding(@encoding)

      if cache && !cache.eof?
        cache.read(length, outbuf)
        outbuf.force_encoding(@encoding)
      end

      until outbuf.bytesize == length || (@buffer.nil? && chunks_depleted?)
        @buffer = retrieve_chunk if @buffer.nil?

        buffered_data = if length && length - outbuf.bytesize < @buffer.bytesize
                          @buffer.byteslice(0, length - outbuf.bytesize)
                        else
                          @buffer
                        end

        outbuf << buffered_data

        cache.write(buffered_data) if cache

        if buffered_data.bytesize < @buffer.bytesize
          @buffer = @buffer.byteslice(buffered_data.bytesize..-1)
        else
          @buffer = nil
        end
      end

      outbuf unless outbuf.empty? && length
    end

    def readpartial(maxlen = nil, outbuf = nil)
      raise IOError, "closed stream" if closed?

      available_length  = 0
      available_length += cache.size - cache.pos if cache
      available_length += @buffer.bytesize if @buffer

      if available_length > 0
        read([available_length, *maxlen].min, outbuf)
      elsif !chunks_depleted?
        read([@next_chunk.bytesize, *maxlen].min, outbuf)
      else
        outbuf.replace("").force_encoding(@encoding) if outbuf
        raise EOFError, "end of file reached"
      end
    end

    def eof?
      raise IOError, "closed stream" if closed?

      return false if cache && !cache.eof?
      @buffer.nil? && chunks_depleted?
    end

    def rewind
      raise IOError, "closed stream" if closed?
      raise IOError, "this Down::ChunkedIO is not rewindable" if cache.nil?

      cache.rewind
    end

    def close
      return if @closed

      chunks_fiber.resume(:terminate) if chunks_fiber.alive?
      @buffer = nil
      cache.close! if cache
      @closed = true
    end

    def closed?
      !!@closed
    end

    def rewindable?
      @rewindable
    end

    def inspect
      string  = String.new
      string << "#<Down::ChunkedIO"
      string << " chunks=#{@chunks.inspect}"
      string << " size=#{size.inspect}"
      string << " encoding=#{encoding.inspect}"
      string << " data=#{data.inspect}"
      string << " on_close=#{@on_close.inspect}"
      string << " rewindable=#{@rewindable.inspect}"
      string << " (closed)" if closed?
      string << ">"
    end

    private

    def cache
      @cache ||= Tempfile.new("down-chunked_io", binmode: true) if @rewindable
    end

    def retrieve_chunk
      chunk = @next_chunk
      @next_chunk = chunks_fiber.resume
      chunk.force_encoding(@encoding) if chunk
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
          @on_close.call if @on_close
        end
      end
    end

    def find_encoding(encoding)
      Encoding.find(encoding)
    rescue ArgumentError
      Encoding::BINARY
    end
  end
end
