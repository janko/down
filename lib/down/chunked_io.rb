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
      @bytes_read = 0

      retrieve_chunk
    end

    def each_chunk
      raise IOError, "closed stream" if closed?

      return enum_for(__method__) if !block_given?
      yield retrieve_chunk until chunks_depleted?
    end

    def read(length = nil, outbuf = nil)
      raise IOError, "closed stream" if closed?

      remaining_length = length

      begin
        data = readpartial(remaining_length, outbuf)
        data = data.dup unless outbuf
        remaining_length = length - data.bytesize if length
      rescue EOFError
      end

      until remaining_length == 0 || eof?
        data << readpartial(remaining_length)
        remaining_length = length - data.bytesize if length
      end

      data.to_s unless length && (data.nil? || data.empty?)
    end

    def gets(separator_or_limit = $/, limit = nil)
      raise IOError, "closed stream" if closed?

      if separator_or_limit.is_a?(Integer)
        separator = $/
        limit     = separator_or_limit
      else
        separator = separator_or_limit
      end

      return read if separator.nil?

      separator = "\n\n" if separator.empty?

      begin
        data = readpartial(limit)

        until data.include?(separator) || data.bytesize == limit || eof?
          remaining_length = limit - data.bytesize if limit
          data << readpartial(remaining_length, outbuf ||= String.new)
        end

        line, extra = data.split(separator, 2)
        line << separator if data.include?(separator)

        if cache
          cache.pos -= extra.to_s.bytesize
        else
          @buffer = @buffer.to_s.prepend(extra.to_s)
        end
      rescue EOFError
        line = nil
      end

      line
    end

    def readpartial(length = nil, outbuf = nil)
      raise IOError, "closed stream" if closed?

      data = outbuf.replace("").force_encoding(@encoding) if outbuf

      if cache && !cache.eof?
        data = cache.read(length, outbuf)
        data.force_encoding(@encoding)
      end

      if @buffer.nil? && (data.nil? || data.empty?)
        raise EOFError, "end of file reached" if chunks_depleted?
        @buffer = retrieve_chunk
      end

      remaining_length = data && length ? length - data.bytesize : length

      unless @buffer.nil? || remaining_length == 0
        buffered_data = if remaining_length && remaining_length < @buffer.bytesize
                          @buffer.byteslice(0, remaining_length)
                        else
                          @buffer
                        end

        if data
          data << buffered_data
        else
          data = buffered_data
        end

        cache.write(buffered_data) if cache

        if buffered_data.bytesize < @buffer.bytesize
          @buffer = @buffer.byteslice(buffered_data.bytesize..-1)
        else
          @buffer = nil
        end
      end

      @bytes_read += data.bytesize

      data
    end

    def pos
      @bytes_read
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
      @bytes_read = 0
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
