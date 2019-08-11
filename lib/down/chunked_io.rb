# frozen-string-literal: true

require "tempfile"
require "fiber"

module Down
  # Wraps an enumerator that yields chunks of content into an IO object. It
  # implements some essential IO methods:
  #
  # * IO#read
  # * IO#readpartial
  # * IO#gets
  # * IO#size
  # * IO#pos
  # * IO#eof?
  # * IO#rewind
  # * IO#close
  #
  # By default the Down::ChunkedIO caches all read content into a tempfile,
  # allowing it to be rewindable. If rewindability won't be used, it can be
  # disabled by setting `:rewindable` to false, which eliminates any disk I/O.
  #
  # Any cleanup code (i.e. ensure block) that the given enumerator carries is
  # guaranteed to get executed, either when all content has been retrieved or
  # when Down::ChunkedIO is closed. One can also specify an `:on_close`
  # callback that will also get executed in those situations.
  class ChunkedIO
    attr_accessor :size, :data, :encoding

    def initialize(chunks:, size: nil, on_close: nil, data: {}, rewindable: true, encoding: nil)
      @chunks     = chunks
      @size       = size
      @on_close   = on_close
      @data       = data
      @encoding   = find_encoding(encoding || "binary")
      @rewindable = rewindable
      @buffer     = nil
      @position   = 0

      retrieve_chunk # fetch first chunk so that we know whether the file is empty
    end

    # Yields elements of the underlying enumerator.
    def each_chunk
      fail IOError, "closed stream" if closed?

      return enum_for(__method__) unless block_given?

      yield retrieve_chunk until chunks_depleted?
    end

    # Implements IO#read semantics. Without arguments it retrieves and returns
    # all content.
    #
    # With `length` argument returns exactly that number of bytes if they're
    # available.
    #
    # With `outbuf` argument each call will return that same string object,
    # where the value is replaced with retrieved content.
    #
    # If end of file is reached, returns empty string if called without
    # arguments, or nil if called with arguments. Raises IOError if closed.
    def read(length = nil, outbuf = nil)
      fail IOError, "closed stream" if closed?

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

      data.to_s unless length && length > 0 && (data.nil? || data.empty?)
    end

    # Implements IO#gets semantics. Without arguments it retrieves lines of
    # content separated by newlines.
    #
    # With `separator` argument it does the following:
    #
    # * if `separator` is a nonempty string returns chunks of content
    #   surrounded with that sequence of bytes
    # * if `separator` is an empty string returns paragraphs of content
    #   (content delimited by two newlines)
    # * if `separator` is nil and `limit` is nil returns all content
    #
    # With `limit` argument returns maximum of that amount of bytes.
    #
    # Returns nil if end of file is reached. Raises IOError if closed.
    def gets(separator_or_limit = $/, limit = nil)
      fail IOError, "closed stream" if closed?

      if separator_or_limit.is_a?(Integer)
        separator = $/
        limit     = separator_or_limit
      else
        separator = separator_or_limit
      end

      return read(limit) if separator.nil?

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

    # Implements IO#readpartial semantics. If there is any content readily
    # available reads from it, otherwise fetches and reads from the next chunk.
    # It writes to and reads from the cache when needed.
    #
    # Without arguments it either returns all content that's readily available,
    # or the next chunk. This is useful when you don't care about the size of
    # chunks and you want to minimize string allocations.
    #
    # With `length` argument returns maximum of that amount of bytes.
    #
    # With `outbuf` argument each call will return that same string object,
    # where the value is replaced with retrieved content.
    #
    # Raises EOFError if end of file is reached. Raises IOError if closed.
    def readpartial(length = nil, outbuf = nil)
      fail IOError, "closed stream" if closed?

      data = outbuf.clear.force_encoding(@encoding) if outbuf

      return data.to_s if length == 0

      if cache && !cache.eof?
        data = cache.read(length, outbuf)
        data.force_encoding(@encoding)
      end

      if @buffer.nil? && (data.nil? || data.empty?)
        fail EOFError, "end of file reached" if chunks_depleted?
        @buffer = retrieve_chunk
      end

      remaining_length = data && length ? length - data.bytesize : length

      unless @buffer.nil? || remaining_length == 0
        if remaining_length && remaining_length < @buffer.bytesize
          buffered_data = @buffer.byteslice(0, remaining_length)
          @buffer       = @buffer.byteslice(remaining_length..-1)
        else
          buffered_data = @buffer
          @buffer       = nil
        end

        if data
          data << buffered_data
        else
          data = buffered_data
        end

        cache.write(buffered_data) if cache

        buffered_data.clear unless buffered_data.equal?(data)
      end

      @position += data.bytesize

      data.force_encoding(Encoding::BINARY) if length
      data
    end

    # Implements IO#pos semantics. Returns the current position of the
    # Down::ChunkedIO.
    def pos
      @position
    end

    # Implements IO#eof? semantics. Returns whether we've reached end of file.
    # It returns true if cache is at the end and there is no more content to
    # retrieve. Raises IOError if closed.
    def eof?
      fail IOError, "closed stream" if closed?

      return false if cache && !cache.eof?
      @buffer.nil? && chunks_depleted?
    end

    # Implements IO#rewind semantics. Rewinds the Down::ChunkedIO by rewinding
    # the cache and setting the position to the beginning of the file. Raises
    # IOError if closed or not rewindable.
    def rewind
      fail IOError, "closed stream" if closed?
      fail IOError, "this Down::ChunkedIO is not rewindable" if cache.nil?

      cache.rewind
      @position = 0
    end

    # Implements IO#close semantics. Closes the Down::ChunkedIO by terminating
    # chunk retrieval and deleting the cached content.
    def close
      return if @closed

      chunks_fiber.resume(:terminate) if chunks_fiber.alive?
      cache.close! if cache
      @buffer = nil
      @closed = true
    end

    # Returns whether the Down::ChunkedIO has been closed.
    def closed?
      !!@closed
    end

    # Returns whether the Down::ChunkedIO was specified as rewindable.
    def rewindable?
      @rewindable
    end

    # Returns useful information about the Down::ChunkedIO object.
    def inspect
      string  = String.new
      string << "#<#{self.class.name}"
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

    # If Down::ChunkedIO is specified as rewindable, returns a new Tempfile for
    # writing read content to. This allows the Down::ChunkedIO to be rewinded.
    def cache
      return if !rewindable?

      @cache ||= (
        tempfile = Tempfile.new("down-chunked_io", binmode: true)
        tempfile.chmod(0000)      # make sure nobody else can read or write to it
        tempfile.unlink if posix? # remove entry from filesystem if it's POSIX
        tempfile
      )
    end

    # Returns current chunk and retrieves the next chunk. If next chunk is nil,
    # we know we've reached EOF.
    def retrieve_chunk
      chunk = @next_chunk
      @next_chunk = chunks_fiber.resume
      chunk.force_encoding(@encoding) if chunk
    end

    # Returns whether there is any content left to retrieve.
    def chunks_depleted?
      !chunks_fiber.alive?
    end

    # Creates a Fiber wrapper around the underlying enumerator. The advantage
    # of using a Fiber here is that we can terminate the chunk retrieval, in a
    # way that executes any cleanup code that the enumerator potentially
    # carries. At the end of iteration the :on_close callback is executed.
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

    # Finds encoding by name. If the encoding couldn't be find, falls back to
    # the generic binary encoding.
    def find_encoding(encoding)
      Encoding.find(encoding)
    rescue ArgumentError
      Encoding::BINARY
    end

    # Returns whether the filesystem has POSIX semantics.
    def posix?
      RUBY_PLATFORM !~ /(mswin|mingw|cygwin|java)/
    end
  end
end
