# frozen-string-literal: true

require "tempfile"
require "stringio"
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
  # * IO#seek
  # * IO#eof?
  # * IO#rewind
  # * IO#close
  #
  # Retrieved chunks are appended to a backing store which the reading methods
  # delegate to, so they behave like the corresponding native IO methods. New
  # chunks are retrieved only when the store runs out of content.
  #
  # By default the store is a tempfile which keeps all read content, allowing
  # the Down::ChunkedIO to be rewindable. If rewindability won't be used, it
  # can be disabled by setting `:rewindable` to false, in which case the store
  # is an in-memory buffer that discards read content, eliminating disk I/O.
  #
  # Any cleanup code (i.e. ensure block) that the given enumerator carries is
  # guaranteed to get executed, either when all content has been retrieved or
  # when Down::ChunkedIO is closed. One can also specify an `:on_close`
  # callback that will also get executed in those situations.
  class ChunkedIO
    attr_accessor :size #: Integer?
    attr_accessor :data #: Hash[Symbol, untyped]
    attr_reader :encoding #: Encoding

    # @rbs @chunks: _Each[String] & Object
    # @rbs @on_close: (^() -> void | (_Callable & Object))?
    # @rbs @rewindable: bool
    # @rbs @next_chunk: String?
    # @rbs @closed: bool
    # @rbs @store: (File | StringIO)?
    # @rbs @stored_bytes: Integer
    # @rbs @trimmed_bytes: Integer
    # @rbs @chunks_fiber: Fiber?

    #: (chunks: _Each[String] & Object, ?size: Integer?, ?on_close: (^() -> void | (_Callable & Object))?, ?data: Hash[Symbol, untyped], ?rewindable: bool, ?encoding: (String | Encoding)?) -> void
    def initialize(chunks:, size: nil, on_close: nil, data: {}, rewindable: true, encoding: nil)
      @chunks        = chunks
      @size          = size
      @on_close      = on_close
      @data          = data
      @encoding      = find_encoding(encoding || "binary")
      @rewindable    = rewindable
      @next_chunk    = nil
      @closed        = false
      @store         = nil
      @stored_bytes  = 0 # number of bytes appended to the store
      @trimmed_bytes = 0 # number of read bytes discarded from the store

      retrieve_chunk # fetch first chunk so that we know whether the file is empty
    end

    # Sets the encoding that read content is returned in.
    #: (String | Encoding encoding) -> void
    def encoding=(encoding)
      @encoding = find_encoding(encoding)
      @store&.set_encoding(@encoding, @encoding)
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
    # where the value is replaced with retrieved content.
    #
    # If end of file is reached, returns empty string if called without
    # arguments, or nil if called with arguments. Raises IOError if closed.
    #: (?nil, ?string? outbuf) -> String
    #: (?int? length, ?string? outbuf) -> String?
    def read(length = nil, outbuf = nil)
      fail IOError, "closed stream" if closed?

      length = length&.to_int # implicit conversion, like IO#read
      outbuf = outbuf&.to_str

      if length
        fill_until(pos + length)
      else
        fill_all
      end

      encoding = outbuf&.encoding if length
      data     = store.read(length, outbuf)
      data&.force_encoding(encoding) if encoding # StringIO < 3.1.2 changes it to binary

      data
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
    # bytes needed to complete a multibyte character.
    #
    # With `chomp: true` removes the trailing separator from the line.
    #
    # Returns nil if end of file is reached. Raises IOError if closed.
    #: (?String? separator, ?Integer? limit, ?chomp: boolish) -> String?
    #: (Integer limit, ?chomp: boolish) -> String?
    def gets(separator_or_limit = $/, limit = nil, chomp: false)
      fail IOError, "closed stream" if closed?

      separator = separator_or_limit.is_a?(Integer) ? $/ : separator_or_limit
      limit     = separator_or_limit if separator_or_limit.is_a?(Integer)

      if separator == "" && store.is_a?(StringIO)
        line = read_paragraph(limit, chomp)
      else
        line = read_line(separator, limit, chomp)
      end

      line
    end

    # Implements IO#readpartial semantics. If there is any content readily
    # available reads from it, otherwise retrieves the next chunk and reads
    # from it.
    #
    # With `maxlen` argument returns maximum of that amount of bytes (default
    # is 16KB).
    #
    # With `outbuf` argument each call will return that same string object,
    # where the value is replaced with retrieved content.
    #
    # Raises EOFError if end of file is reached. Raises IOError if closed.
    #: (?int? maxlen, ?string? outbuf) -> String
    def readpartial(maxlen = nil, outbuf = nil)
      fail IOError, "closed stream" if closed?

      maxlen = maxlen ? maxlen.to_int : 16*1024 # implicit conversion, like IO#readpartial

      fill_chunk while maxlen > 0 && pos >= @stored_bytes && !chunks_depleted?

      # Reading only stored content allocates a string of that size, instead
      # of maxlen bytes, which also avoids reallocating a reused buffer.
      maxlen = [maxlen, @stored_bytes - pos].min if pos < @stored_bytes

      outbuf   = outbuf&.to_str
      encoding = outbuf&.encoding
      data     = outbuf ? store.readpartial(maxlen, outbuf) : store.readpartial(maxlen) # JRuby rejects nil outbuf
      data.force_encoding(encoding) if encoding # StringIO < 3.1.2 changes it to binary

      data
    end

    # Implements IO#seek semantics. It retrieves content up to the target
    # position. Raises Errno::ESPIPE if not rewindable.
    #: (int amount, ?(Integer | Symbol) whence) -> Integer
    def seek(amount, whence = IO::SEEK_SET)
      fail IOError, "closed stream" if closed?
      fail Errno::ESPIPE unless rewindable?

      amount = amount.to_int

      case whence
      when IO::SEEK_SET, :SET
        whence = IO::SEEK_SET
        fill_until(amount)
      when IO::SEEK_CUR, :CUR
        whence = IO::SEEK_CUR
        fill_until(pos + amount)
      when IO::SEEK_END, :END
        whence = IO::SEEK_END
        fill_all
      else
        fail ArgumentError, "invalid whence: #{whence.inspect}"
      end

      store.seek(amount, whence)
    end

    # Implements IO#pos semantics. Returns the current position of the
    # Down::ChunkedIO. Raises IOError if closed.
    #: () -> Integer
    def pos
      fail IOError, "closed stream" if closed?

      @trimmed_bytes + store.pos
    end
    alias tell pos

    # Implements IO#eof? semantics. Returns whether we've reached end of file.
    # It returns true if the store is at the end and there is no more content
    # to retrieve. Raises IOError if closed.
    #: () -> bool
    def eof?
      fail IOError, "closed stream" if closed?

      pos >= @stored_bytes && chunks_depleted?
    end
    alias eof eof?

    # Implements IO#rewind semantics. Rewinds the Down::ChunkedIO by setting
    # the position to the beginning of the file. Raises IOError if closed or
    # not rewindable.
    #: () -> Integer
    def rewind
      fail IOError, "closed stream" if closed?
      fail IOError, "this Down::ChunkedIO is not rewindable" unless rewindable?

      store.rewind
    end

    # Implements IO#close semantics. Closes the Down::ChunkedIO by terminating
    # chunk retrieval and deleting the retrieved content.
    #: () -> void
    def close
      return if @closed

      chunks_fiber.resume(:terminate) if chunks_fiber.alive?

      @store&.close
      @store  = nil
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

    # Returns the IO object that retrieved content is appended to and read
    # from. If Down::ChunkedIO is specified as rewindable, it's an anonymous
    # tempfile which keeps all retrieved content, otherwise it's a StringIO
    # from which read content gets discarded.
    # @rbs %a{pure}
    #: () -> (File | StringIO)
    def store
      @store ||= (
        if rewindable?
          # the file is already deleted (or never named on Linux), so it gets
          # cleaned up once closed, and no other process can open it
          store = Tempfile.create("down-chunked_io", anonymous: true)
          store.binmode # anonymous tempfiles ignore the :binmode option
        else
          store = StringIO.new(String.new(encoding: Encoding::BINARY))
        end

        # passing the same internal encoding disables Encoding.default_internal
        store.set_encoding(@encoding, @encoding)
        store
      )
    end

    # Reads a line from the store, retrieving more content if the line might
    # continue in content that wasn't retrieved yet.
    #: (String? separator, Integer? limit, boolish chomp) -> String?
    def read_line(separator, limit, chomp)
      start = store.pos
      line  = nil #: String?

      loop do
        line = store.gets(separator, limit, chomp:)

        # JRuby's StringIO returns a truncated line and moves to a wrong
        # position when the limit cuts a multibyte character that's incomplete
        # at the end of the store. Like IO, we return the remaining content at
        # the end of file, otherwise we retry with more content.
        if RUBY_ENGINE == "jruby" && line && truncated_line?(separator, limit, start)
          store.pos = start
          line      = chunks_depleted? ? store.read : nil
        end

        # If the store ran out of content, the line might continue in content
        # that wasn't retrieved yet. In that case we retrieve more content and
        # read the line again, at least doubling the content after the line
        # start, so that lines spanning many chunks aren't re-read many times.
        # StringIO doesn't move to the end when only newlines are left in
        # paragraph mode, so we also retrieve more content when there's no line.
        break if chunks_depleted?
        break unless line.nil? || store.eof?
        break if line_complete?(line, separator, limit, start)

        store.pos = start # keeps the line start in the store when retrieving content
        fill_until(@stored_bytes + [@stored_bytes - @trimmed_bytes - start, 1].max)
        start = store.pos # retrieving content can discard content before it
      end

      store.seek(0, IO::SEEK_END) if line.nil? # skipped newlines in paragraph mode

      line
    end

    # Reads a paragraph from a StringIO store. StringIO's paragraph mode
    # differs from IO's in how it applies the limit and chomps lines, so we
    # implement it on top of the double-newline separator, like IO does.
    #: (Integer? limit, boolish chomp) -> String?
    def read_paragraph(limit, chomp)
      skip_newlines

      line = read_line("\n\n", limit, chomp)

      skip_newlines if line # IO skips them even when the limit cut the line

      line
    end

    # Moves the store position past any consecutive newlines, retrieving more
    # content as needed.
    #: () -> void
    def skip_newlines
      loop do
        fill_chunk while store.eof? && !chunks_depleted?

        byte = store.getbyte
        next if byte == 10 # newline

        store.pos -= 1 if byte
        break
      end
    end

    # Returns whether the line just read from the given start position of a
    # StringIO store was truncated. A line read with a positive limit that
    # stops before the end of the store must reach the limit or end with the
    # separator, which JRuby's StringIO violates when the limit cuts a
    # multibyte character that's incomplete at the end of the store.
    #: (String? separator, Integer? limit, Integer start) -> bool
    def truncated_line?(separator, limit, start)
      return false unless store.is_a?(StringIO) && limit && limit > 0

      line_bytes = store.pos - start

      return false if line_bytes >= limit || store.eof?

      if separator.is_a?(String) && !separator.empty? && line_bytes >= separator.bytesize
        return false if store_bytes(store.pos - separator.bytesize, separator.bytesize) == separator.b
      end

      true
    end

    # Returns whether the line read from the given start position of the store
    # can't continue in content that wasn't retrieved yet, which is when it
    # ends with the separator or reaches the limit with a complete character.
    # In paragraph mode it's never complete, as newlines after it are skipped.
    #: (String? line, String? separator, Integer? limit, Integer start) -> bool
    def line_complete?(line, separator, limit, start)
      return false if line.nil? || separator == ""

      line_bytes = store.pos - start

      if separator.is_a?(String) && !separator.empty? && line_bytes >= separator.bytesize
        return true if store_bytes(store.pos - separator.bytesize, separator.bytesize) == separator.b
      end

      return true if limit && limit >= 0 && line_bytes >= limit && line.valid_encoding?

      false
    end

    # Returns the given number of bytes stored at the given store position.
    #: (Integer position, Integer length) -> String
    def store_bytes(position, length)
      case store
      when File     then store.pread(length, position)
      when StringIO then store.string.byteslice(position, length).to_s.b
      end
    end

    # Retrieves the next chunk and appends it to the store, without changing
    # the store position. Returns false if there are no more chunks.
    #: () -> bool
    def fill_chunk
      return false if chunks_depleted?

      chunk = retrieve_chunk #: String

      case store
      when File
        # unlike #write, #pwrite writes bytes as they are, without transcoding
        store.pwrite(chunk, @stored_bytes)
      when StringIO
        read_bytes   = store.pos
        unread_bytes = store.string.bytesize - read_bytes

        if unread_bytes == 0
          # A copy shares the chunk's memory until either is modified, so all
          # read content is discarded without copying the chunk.
          string = chunk.dup
        elsif read_bytes >= unread_bytes
          # Strings read up to the end of the store share its memory, making
          # appending copy the whole store. Copying only unread content instead
          # discards read content, and copies fewer bytes than were read.
          unread = store.string.force_encoding(Encoding::BINARY).byteslice(read_bytes, unread_bytes).to_s
          string = String.new(capacity: unread_bytes + chunk.bytesize, encoding: Encoding::BINARY)
          string << unread << chunk
        else
          # appending in binary encoding prevents encoding compatibility errors
          store.string.force_encoding(Encoding::BINARY) << chunk
          store.string.force_encoding(@encoding)
        end

        if string
          @trimmed_bytes += read_bytes
          store.string    = string.force_encoding(@encoding)
        end
      end

      @stored_bytes += chunk.bytesize

      true
    end

    # Retrieves chunks until the store holds content up to the given
    # position, or until there are no more chunks.
    #: (Integer position) -> void
    def fill_until(position)
      fill_chunk while @stored_bytes < position && !chunks_depleted?
    end

    # Retrieves all remaining chunks.
    #: () -> void
    def fill_all
      fill_chunk until chunks_depleted?
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
  end
end
