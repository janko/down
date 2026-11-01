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
    attr_accessor :size #: Integer?
    attr_accessor :data #: Hash[Symbol, untyped]
    attr_accessor :encoding #: Encoding

    # @rbs @chunks: _Each[String] & Object
    # @rbs @on_close: (^() -> void | (_Callable & Object))?
    # @rbs @rewindable: bool
    # @rbs @buffer: String?
    # @rbs @position: Integer
    # @rbs @next_chunk: String?
    # @rbs @closed: bool
    # @rbs @cache: Tempfile?
    # @rbs @chunks_fiber: Fiber?

    #: (chunks: _Each[String] & Object, ?size: Integer?, ?on_close: (^() -> void | (_Callable & Object))?, ?data: Hash[Symbol, untyped], ?rewindable: bool, ?encoding: (String | Encoding)?) -> void
    def initialize(chunks:, size: nil, on_close: nil, data: {}, rewindable: true, encoding: nil)
      @chunks     = chunks
      @size       = size
      @on_close   = on_close
      @data       = data
      @encoding   = find_encoding(encoding || "binary")
      @rewindable = rewindable
      @buffer     = nil
      @position   = 0
      @next_chunk = nil
      @closed     = false

      retrieve_chunk # fetch first chunk so that we know whether the file is empty
    end

    # For compatibility with multipart-post gem.
    #: () -> Integer?
    def length
      @size
    end

    # Yields elements of the underlying enumerator.
    #: () { (String) -> void } -> void
    #: () -> Enumerator[String, void]
    def each_chunk
      fail IOError, "closed stream" if closed?

      return enum_for(:each_chunk) unless block_given?

      until chunks_depleted?
        chunk = retrieve_chunk #: String
        yield chunk
      end
    end

    # Implements IO#read semantics. Without arguments it retrieves and returns
    # all content in the external encoding.
    #
    # With `length` argument returns exactly that number of bytes if they're
    # available, as a binary string.
    #
    # With `outbuf` argument each call will return that same string object,
    # where the value is replaced with retrieved content. When `length` is
    # given, the buffer keeps its encoding.
    #
    # If end of file is reached, returns empty string if called without
    # arguments, or nil if called with arguments. Raises IOError if closed.
    #: (?nil, ?string? outbuf) -> String
    #: (?int? length, ?string? outbuf) -> String?
    def read(length = nil, outbuf = nil)
      # Implicit conversion, like IO#read
      length = length.to_int if length
      fail ArgumentError, "negative length #{length} given" if length && length < 0
      outbuf = outbuf.to_str if outbuf

      fail IOError, "closed stream" if closed?

      encoding = length ? (outbuf&.encoding || Encoding::BINARY) : @encoding
      data     = outbuf ? outbuf.clear.force_encoding(Encoding::BINARY) : "".b

      remaining_length = length

      until remaining_length == 0 || eof?
        data << readpartial(remaining_length, buffer ||= "".b)
        remaining_length = length - data.bytesize if length
      end

      buffer.clear if buffer # deallocate string

      data.force_encoding(encoding)
      data unless data.empty? && length && length > 0
    end

    # Implements IO#gets semantics. Without arguments it retrieves lines of
    # content separated by newlines.
    #
    # With `separator` argument it does the following:
    #
    # * if `separator` is a nonempty string returns chunks of content
    #   surrounded with that sequence of bytes
    # * if `separator` is an empty string returns paragraphs of content
    #   (content delimited by two or more newlines, which are skipped)
    # * if `separator` is nil returns all content
    #
    # With `limit` argument returns maximum of that amount of bytes, plus any
    # bytes needed to complete a multibyte character. A negative limit means no
    # limit, and a zero limit returns an empty string.
    #
    # With `chomp: true` removes the trailing separator from the line.
    #
    # Returns nil if end of file is reached. Raises IOError if closed.
    #: (?String? separator, ?Integer? limit, ?chomp: boolish) -> String?
    #: (Integer limit, ?chomp: boolish) -> String?
    def gets(separator_or_limit = $/, limit = nil, chomp: false)
      fail IOError, "closed stream" if closed?

      if separator_or_limit.is_a?(Integer)
        separator = $/
        limit     = separator_or_limit
      else
        separator = separator_or_limit
      end

      limit = nil if limit && limit < 0 # negative limit means no limit

      return String.new(encoding: @encoding) if limit == 0

      paragraph = separator == ""
      separator = paragraph ? "\n\n".b : separator&.b

      skip_newlines if paragraph

      line = read_line(separator, limit)

      return nil if line.nil?

      skip_newlines if paragraph

      if chomp && separator && line.end_with?(separator)
        line = line.byteslice(0, line.bytesize - separator.bytesize) #: String
        line.chomp!("\r") if separator == "\n"
      end

      line.force_encoding(@encoding)
    end

    # Implements IO#readpartial semantics. If there is any content readily
    # available reads from it, otherwise fetches and reads from the next chunk.
    # It writes to and reads from the cache when needed.
    #
    # Without arguments it either returns all content that's readily available,
    # or the next chunk. This is useful when you don't care about the size of
    # chunks and you want to minimize string allocations.
    #
    # With `maxlen` argument returns maximum of that amount of bytes (default
    # is 16KB).
    #
    # With `outbuf` argument each call will return that same string object,
    # where the value is replaced with retrieved content. The returned string
    # has the encoding of `outbuf`, or is binary when `outbuf` isn't given.
    #
    # Raises EOFError if end of file is reached. Raises IOError if closed.
    #: (?int? maxlen, ?string? outbuf) -> String
    def readpartial(maxlen = nil, outbuf = nil)
      # Implicit conversion, like IO#readpartial
      maxlen = maxlen ? maxlen.to_int : 16*1024
      fail ArgumentError, "negative length #{maxlen} given" if maxlen < 0
      outbuf = outbuf.to_str if outbuf

      fail IOError, "closed stream" if closed?

      encoding = outbuf ? outbuf.encoding : Encoding::BINARY
      data     = outbuf ? outbuf.clear.force_encoding(Encoding::BINARY) : "".b

      return data.force_encoding(encoding) if maxlen == 0

      cache.read(maxlen, data) if cache && !cache.eof?

      if @buffer.nil? && data.empty?
        if chunks_depleted?
          data.force_encoding(encoding)
          fail EOFError, "end of file reached"
        end

        @buffer = retrieve_chunk
      end

      remaining_length = maxlen - data.bytesize

      buffer = @buffer

      unless buffer.nil? || remaining_length == 0
        if remaining_length < buffer.bytesize
          buffered_data = buffer.byteslice(0, remaining_length) #: String
          @buffer       = buffer.byteslice(remaining_length..-1)
        else
          buffered_data = buffer
          @buffer       = nil
        end

        data << buffered_data

        cache.write(buffered_data) if cache

        buffered_data.clear unless buffered_data.frozen?
      end

      @position += data.bytesize

      data.force_encoding(encoding)
    end

    # Implements IO#seek semantics. Like IO#seek, it allows seeking beyond end
    # of file, and returns 0.
    #: (int amount, ?(Integer | Symbol) whence) -> Integer
    def seek(amount, whence = IO::SEEK_SET)
      fail IOError, "closed stream" if closed?
      fail Errno::ESPIPE if cache.nil?

      amount = amount.to_int
      original_position = @position

      case whence
      when IO::SEEK_SET, :SET
        target_pos = amount
      when IO::SEEK_CUR, :CUR
        target_pos = @position + amount
      when IO::SEEK_END, :END
        unless chunks_depleted? && @buffer.nil?
          cache.seek(0, IO::SEEK_END)
          IO.copy_stream(self, File::NULL)
        end

        target_pos = cache.size + amount
      else
        fail ArgumentError, "invalid whence: #{whence.inspect}"
      end

      # retrieve content up to the target position, if it's not cached yet
      if target_pos > cache.size
        cache.seek(0, IO::SEEK_END)
        IO.copy_stream(self, File::NULL, target_pos - cache.size)
      end

      begin
        cache.seek(target_pos)
      rescue SystemCallError # e.g. seeking before start of file
        # restore position changed by retrieving content
        cache.seek(original_position)
        @position = original_position
        raise
      end

      @position = target_pos

      0
    end

    # Implements IO#pos semantics. Returns the current position of the
    # Down::ChunkedIO. Raises IOError if closed.
    #: () -> Integer
    def pos
      fail IOError, "closed stream" if closed?

      @position
    end
    alias tell pos

    # Implements IO#eof? semantics. Returns whether we've reached end of file.
    # It returns true if cache is at the end and there is no more content to
    # retrieve. Raises IOError if closed.
    #: () -> bool
    def eof?
      fail IOError, "closed stream" if closed?

      return false if cache && !cache.eof?
      @buffer.nil? && chunks_depleted?
    end
    alias eof eof?

    # Implements IO#rewind semantics. Rewinds the Down::ChunkedIO by rewinding
    # the cache and setting the position to the beginning of the file. Raises
    # IOError if closed or not rewindable.
    #: () -> Integer
    def rewind
      fail IOError, "closed stream" if closed?
      fail IOError, "this Down::ChunkedIO is not rewindable" if cache.nil?

      cache.rewind
      @position = 0
    end

    # Implements IO#close semantics. Closes the Down::ChunkedIO by terminating
    # chunk retrieval and deleting the cached content.
    #: () -> void
    def close
      return if @closed

      chunks_fiber.resume(:terminate) if chunks_fiber.alive?
      cache.close! if cache
      @buffer = nil
      @closed = true
    end

    # Returns whether the Down::ChunkedIO has been closed.
    #: () -> bool
    def closed?
      !!@closed
    end

    # Returns whether the Down::ChunkedIO was specified as rewindable.
    #: () -> bool
    def rewindable?
      @rewindable
    end

    # Returns useful information about the Down::ChunkedIO object.
    #: () -> String
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
    # @rbs %a{pure}
    #: () -> Tempfile?
    def cache
      return if !rewindable?

      @cache ||= (
        tempfile = Tempfile.new("down-chunked_io", binmode: true)
        tempfile.chmod(0000)      # make sure nobody else can read or write to it
        tempfile.unlink if posix? # remove entry from filesystem if it's POSIX
        tempfile
      )
    end

    # Reads content up to and including the separator, or up to the limit
    # (completing a multibyte character if the limit cuts it). Any content read
    # beyond that is put back. Returns nil if end of file is reached.
    #: (String? separator, Integer? limit) -> String?
    def read_line(separator, limit)
      return nil if eof?

      # read a few bytes beyond the limit, in case they complete a character
      read_limit  = limit + MAX_CHAR_COMPLETION if limit && @encoding != Encoding::BINARY
      read_limit ||= limit

      data        = "".b
      buffer      = nil #: String?
      search_from = 0
      line_end    = nil #: Integer?

      loop do
        if separator && (index = data.byteindex(separator, search_from))
          line_end = index + separator.bytesize
          break
        end

        break if eof? || (read_limit && data.bytesize >= read_limit)

        # the separator might start within the bytes we've already searched
        search_from = [data.bytesize - (separator&.bytesize || 0) + 1, 0].max

        remaining_length = read_limit - data.bytesize if read_limit
        data << readpartial(remaining_length, buffer ||= "".b)
      end

      buffer.clear if buffer # deallocate string

      line_end ||= data.bytesize
      line_end   = limit + char_completion(data, limit) if limit && line_end > limit

      line  = data.byteslice(0, line_end) #: String
      extra = data.byteslice(line_end..) #: String

      unread(extra) unless extra.empty?

      data.clear # deallocate string

      line
    end

    # Reads and discards consecutive newlines, used for paragraph mode.
    #: () -> void
    def skip_newlines
      until eof?
        data  = readpartial
        index = data.index(/[^\n]/n)

        if index
          unread(data.byteslice(index..).to_s)
          break
        end
      end
    end

    # Puts back content that was read, so that it's returned by the next read.
    #: (String data) -> void
    def unread(data)
      @position -= data.bytesize

      if cache
        cache.pos -= data.bytesize
      elsif (existing_buffer = @buffer)
        existing_buffer.prepend(data)
      else
        @buffer = data
      end
    end

    # The maximum number of bytes needed to complete a multibyte character cut
    # at the end of a line (characters are at most 4 bytes in common encodings).
    MAX_CHAR_COMPLETION = 3
    private_constant :MAX_CHAR_COMPLETION

    # Returns the number of bytes after `offset` needed to complete a multibyte
    # character that `offset` cuts in half, or 0 if it doesn't cut one. Like
    # IO#gets, it only completes characters which are valid in the encoding.
    #: (String data, Integer offset) -> Integer
    def char_completion(data, offset)
      return 0 if @encoding == Encoding::BINARY

      (1..MAX_CHAR_COMPLETION).each do |head_size|
        break if head_size > offset

        head = data.byteslice(offset - head_size, head_size).to_s.force_encoding(@encoding)
        next if head.valid_encoding? # the bytes before offset are complete characters

        (1..MAX_CHAR_COMPLETION + 1 - head_size).each do |completion_size|
          char = data.byteslice(offset - head_size, head_size + completion_size).to_s
          break if char.bytesize < head_size + completion_size # not enough content

          char.force_encoding(@encoding)
          return completion_size if char.valid_encoding? && char.length == 1
        end
      end

      0
    end

    # Returns current chunk and retrieves the next chunk, skipping empty ones.
    # If there are no more chunks, we know we've reached EOF.
    #: () -> String?
    def retrieve_chunk
      chunk = @next_chunk

      loop do
        @next_chunk = chunks_fiber.resume
        break unless chunks_fiber.alive? && @next_chunk == ""
      end

      # work with raw bytes, as chunks in other encodings can't be combined
      chunk = chunk.b if chunk && chunk.encoding != Encoding::BINARY

      chunk
    end

    # Returns whether there is any content left to retrieve.
    #: () -> bool
    def chunks_depleted?
      !chunks_fiber.alive?
    end

    # Creates a Fiber wrapper around the underlying enumerator. The advantage
    # of using a Fiber here is that we can terminate the chunk retrieval, in a
    # way that executes any cleanup code that the enumerator potentially
    # carries. At the end of iteration the :on_close callback is executed.
    #: () -> Fiber
    def chunks_fiber
      @chunks_fiber ||= Fiber.new do
        begin
          @chunks.each do |chunk|
            action = Fiber.yield chunk
            break if action == :terminate
          end
        ensure
          @on_close&.call
        end
      end
    end

    # Finds encoding by name. If the encoding couldn't be find, falls back to
    # the generic binary encoding.
    #: (String | Encoding encoding) -> Encoding
    def find_encoding(encoding)
      Encoding.find(encoding) #: Encoding
    rescue ArgumentError
      Encoding::BINARY
    end

    # Returns whether the filesystem has POSIX semantics.
    #: () -> bool
    def posix?
      RUBY_PLATFORM !~ /(mswin|mingw|cygwin|java)/
    end
  end
end
