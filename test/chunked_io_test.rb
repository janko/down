# frozen_string_literal: true

require "test_helper"
require "down/chunked_io"
require "timeout"

describe Down::ChunkedIO do
  def chunked_io(**options)
    Down::ChunkedIO.new(**options)
  end

  describe "#initialize" do
    it "requires :chunks" do
      assert_raises(ArgumentError) { chunked_io }
    end

    it "accepts :size" do
      io = chunked_io(chunks: [].each, size: 3)
      assert_equal 3, io.size
    end

    it "accepts :data" do
      io = chunked_io(chunks: [].each, data: {foo: "bar"})
      assert_equal "bar", io.data[:foo]
    end

    it "accepts :encoding" do
      assert_equal Encoding::BINARY, chunked_io(chunks: [].each).encoding
      assert_equal Encoding::UTF_8,  chunked_io(chunks: [].each, encoding: "utf-8").encoding
      assert_equal Encoding::UTF_8,  chunked_io(chunks: [].each, encoding: Encoding::UTF_8).encoding
      assert_equal Encoding::BINARY, chunked_io(chunks: [].each, encoding: "unknown").encoding
    end

    it "retreives the first chunk" do
      exceptional_chunks = Enumerator.new { |y| raise Timeout::Error }
      assert_raises(Timeout::Error) { chunked_io(chunks: exceptional_chunks) }
    end
  end

  describe "#read" do
    describe "without arguments" do
      it "reads whole content" do
        io = chunked_io(chunks: ["abc"].each)
        assert_equal "abc", io.read
      end

      it "reads across chunks" do
        io = chunked_io(chunks: ["ab", "cd", "e"].each)
        assert_equal "abcde", io.read
      end

      it "reads remaining content" do
        io = chunked_io(chunks: ["abc"].each)
        io.read(1)
        assert_equal "bc", io.read
      end

      it "reads from cache" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        io.rewind
        assert_equal "abc", io.read
      end

      it "seamlessly switches between reading cached and new content" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1)
        io.rewind
        assert_equal "abc", io.read
      end

      it "returns empty string on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        assert_equal "", io.read
      end

      it "returns empty string on zero chunks" do
        io = chunked_io(chunks: [].each)
        assert_equal "", io.read
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        io.read(1)
        assert_equal "bc", io.read
      end

      it "returns content in specified encoding" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal Encoding::BINARY, io.read.encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read.encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::UTF_8, io.read.encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read.encoding
      end
    end

    describe "with length" do
      it "reads specified number of bytes" do
        io = chunked_io(chunks: ["abc"].each)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end

      it "reads across chunks" do
        io = chunked_io(chunks: ["ab", "cd", "e"].each)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
        assert_equal "de", io.read(2)
      end

      it "reads as much as it can read" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "abc", io.read(4)
      end

      it "returns empty string when length is zero" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "",    io.read(0)
        assert_equal "abc", io.read
      end

      it "reads from cache" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1)
        io.rewind
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end

      it "seamlessly switches between reading cached and new content" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1)
        io.rewind
        assert_equal "ab", io.read(2)
      end

      it "returns nil on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        assert_nil io.read(1)
      end

      it "returns nil on zero chunks" do
        io = chunked_io(chunks: [].each)
        assert_nil io.read(1)
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end

      it "returns content in binary encoding" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal Encoding::BINARY, io.read(1).encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read(1).encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::BINARY, io.read(1).encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read(1).encoding
      end
    end

    describe "with length and buffer" do
      it "reads specified number of bytes" do
        io = chunked_io(chunks: ["abc"].each)
        assert_equal "a",  io.read(1, "".dup)
        assert_equal "bc", io.read(2, "".dup)
      end

      it "reads across chunks" do
        io = chunked_io(chunks: ["ab", "cd", "e"].each)
        assert_equal "a",  io.read(1, "".dup)
        assert_equal "bc", io.read(2, "".dup)
        assert_equal "de", io.read(2, "".dup)
      end

      it "writes read content into the buffer" do
        io = chunked_io(chunks: ["abc"].each)
        buffer = "".dup
        io.read(1, buffer)
        assert_equal "a", buffer
        io.read(2, buffer)
        assert_equal "bc", buffer
      end

      it "returns the buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = "".dup
        assert_equal buffer.object_id, io.read(1, buffer).object_id
        assert_equal buffer.object_id, io.read(2, buffer).object_id
        io.rewind
        assert_equal buffer.object_id, io.read(1, buffer).object_id
        assert_equal buffer.object_id, io.read(2, buffer).object_id
      end

      it "reads as much as it can read" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "abc", io.read(4, "".dup)
      end

      it "returns empty string when length is zero" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = "".dup
        assert_equal "",               io.read(0, buffer)
        assert_equal buffer.object_id, io.read(0, buffer).object_id
        assert_equal "abc", io.read
      end

      it "reads from cache" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1, "".dup)
        io.rewind
        assert_equal "a",  io.read(1, "".dup)
        assert_equal "bc", io.read(2, "".dup)
      end

      it "seamlessly switches between reading cached and new content" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1, "".dup)
        io.rewind
        assert_equal "abc", io.read(3, "".dup)
      end

      it "returns nil on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        buffer = "buffer".dup
        assert_nil io.read(1, buffer)
        assert_equal "", buffer
      end

      it "returns nil on zero chunks" do
        io = chunked_io(chunks: [].each)
        buffer = "buffer".dup
        assert_nil io.read(1, buffer)
        assert_equal "", buffer
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        assert_equal "a",  io.read(1, "".dup)
        assert_equal "bc", io.read(2, "".dup)
      end

      it "returns content in the encoding of the buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal Encoding::UTF_8, io.read(1, "".dup).encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read(1, "".dup).encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read(1, "".b).encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::BINARY, io.read(1, "".b).encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read(1, "".dup).encoding
      end
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.read }
    end

    it "raises ArgumentError on negative length" do
      io = chunked_io(chunks: ["ab", "c"].each)
      error = assert_raises(ArgumentError) { io.read(-1) }
      assert_equal "negative length -1 given", error.message
    end

    it "keeps the buffer encoding at end of file" do
      io = chunked_io(chunks: ["ab"].each)
      io.read
      buffer = "garbage".dup
      assert_nil io.read(1, buffer)
      assert_equal "", buffer
      assert_equal Encoding::UTF_8, buffer.encoding
    end

    it "handles chunks in non-binary encodings" do
      io = chunked_io(chunks: ["€a", "é"].each)
      io.read(1)
      io.rewind
      assert_equal "€a".b, io.read(4)
      assert_equal "é".b,  io.read
    end
  end

  describe "#gets" do
    it "retrieves lines" do
      io = chunked_io(chunks: ["a\n", "b\nc\nd", "\n"].each)
      assert_equal "a\n", io.gets
      assert_equal "b\n", io.gets
      assert_equal "c\n", io.gets
      assert_equal "d\n", io.gets
    end

    it "retrieves lines when non-rewindable" do
      io = chunked_io(chunks: ["a\n", "b\nc\nd", "\n"].each, rewindable: false)
      assert_equal "a\n", io.gets
      assert_equal "b\n", io.gets
      assert_equal "c\n", io.gets
      assert_equal "d\n", io.gets
    end

    it "retrieves lines when non-rewindable with limit" do
      io = chunked_io(chunks: ["a\n", "b\nc\nd", "\n"].each, rewindable: false)
      assert_equal "a\n", io.gets(3)
      assert_equal "b\n", io.gets(3)
      assert_equal "c\n", io.gets(3)
      assert_equal "d\n", io.gets(3)
    end

    it "accepts a different separator" do
      io = chunked_io(chunks: ["a\r", "b\rc\rd", "\r"].each)
      assert_equal "a\r", io.gets("\r")
      assert_equal "b\r", io.gets("\r")
      assert_equal "c\r", io.gets("\r")
      assert_equal "d\r", io.gets("\r")
    end

    it "reads the whole file when separator and limit are nil" do
      io = chunked_io(chunks: ["a\n", "b\nc\nd", "\n"].each)
      assert_equal "a\nb\nc\n\d\n", io.gets(nil)
    end

    it "uses the double-newline separator when separator is empty" do
      io = chunked_io(chunks: ["a\n", "b\n\n\nd", "\n"].each)
      assert_equal "a\nb\n\n", io.gets("")
      assert_equal "d\n",      io.gets("")
    end

    it "accepts a limit" do
      io = chunked_io(chunks: ["a", "b", "c\n"].each)
      assert_equal "a",  io.gets(1)
      assert_equal "bc", io.gets(2)
      assert_equal "\n", io.gets(3)
    end

    it "accepts a separator and a limit" do
      io = chunked_io(chunks: ["a", "bc\r", "d\r"].each)
      assert_equal "ab",  io.gets("\r", 2)
      assert_equal "c\r", io.gets("\r", 3)
      assert_equal "d\r", io.gets("\r", 3)
    end

    it "accepts a nil separator and a limit" do
      io = chunked_io(chunks: ["a", "bc\r", "d\r"].each)
      assert_equal "ab",   io.gets(nil, 2)
      assert_equal "c\rd", io.gets(nil, 3)
      assert_equal "\r",   io.gets(nil, 3)
    end

    it "returns lines in sepecified encoding" do
      io = chunked_io(chunks: ["ab", "c"], encoding: Encoding::UTF_8)
      assert_equal Encoding::UTF_8, io.gets.encoding

      io = chunked_io(chunks: ["ab", "c"])
      assert_equal Encoding::BINARY, io.gets.encoding
    end

    it "returns content in specified encoding when separator is nil" do
      io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
      assert_equal Encoding::UTF_8, io.gets(nil).encoding

      io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
      assert_equal Encoding::UTF_8, io.gets(nil, 2).encoding

      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal Encoding::BINARY, io.gets(nil).encoding

      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal Encoding::BINARY, io.gets(nil, 2).encoding
    end

    it "returns nil when on EOF" do
      io = chunked_io(chunks: ["a\n"].each)
      io.gets
      assert_nil io.gets
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["a\n"])
      io.close
      assert_raises(IOError) { io.gets }
    end

    it "updates #pos" do
      io = chunked_io(chunks: ["a\nb\nc\n"].each)
      assert_equal 0, io.pos
      io.gets
      assert_equal 2, io.pos
      io.gets
      assert_equal 4, io.pos
      io.gets
      assert_equal 6, io.pos
    end

    it "returns nil at end of file when separator is nil" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal "abc", io.gets(nil)
      assert_nil io.gets(nil)
    end

    it "skips newlines around paragraphs" do
      io = chunked_io(chunks: ["\n\n\nfoo\nbar", "\n\n\n\nbaz\n"].each)
      assert_equal "foo\nbar\n\n", io.gets("")
      assert_equal 14, io.pos
      assert_equal "baz\n", io.gets("")
      assert_nil io.gets("")
    end

    it "returns nil in paragraph mode when there are only newlines left" do
      io = chunked_io(chunks: ["\n\n", "\n"].each)
      assert_nil io.gets("")
      assert_equal 3, io.pos
    end

    it "accepts :chomp" do
      io = chunked_io(chunks: ["a\r\nb\n", "c--d--", "\n\ne\n\n", "f"].each)
      assert_equal "a", io.gets(chomp: true)
      assert_equal "b", io.gets("\n", chomp: true)
      assert_equal "c", io.gets("--", chomp: true)
      assert_equal "d", io.gets("--", 1, chomp: true) + io.gets("--", chomp: true)
      assert_equal "e", io.gets("", chomp: true)
      assert_equal "f", io.gets(nil, chomp: true)
    end

    it "returns an empty string with zero limit" do
      io = chunked_io(chunks: ["ab"].each)
      assert_equal "", io.gets(0)
      io.read
      assert_equal "", io.gets(0)
    end

    it "treats negative limit as no limit" do
      io = chunked_io(chunks: ["ab\n", "cd"].each)
      assert_equal "ab\n", io.gets(-1)
      assert_equal "cd",   io.gets("\n", -5)
    end

    it "completes multibyte characters cut by the limit" do
      io = chunked_io(chunks: ["aé", "€ b"].each, encoding: "utf-8")
      assert_equal "aé", io.gets(2)
      assert_equal "€",  io.gets(1)
      assert_equal " b", io.gets(2)
    end

    it "doesn't complete invalid characters cut by the limit" do
      io = chunked_io(chunks: ["a\xFF\xFEb".b].each, encoding: "utf-8")
      assert_equal "a\xFF".dup.force_encoding("utf-8"), io.gets(2)
    end

    it "doesn't complete characters in binary encoding" do
      io = chunked_io(chunks: ["aé"].each)
      assert_equal "a\xC3".b, io.gets(2)
    end

    it "puts back extra content when not rewindable" do
      io = chunked_io(chunks: ["a\nb", "\nc"].each, rewindable: false)
      assert_equal "a\n", io.gets
      assert_equal "b\n", io.gets
      assert_equal "c",   io.gets
    end
  end

  describe "#readpartial" do
    describe "with maxlen" do
      it "reads specified number of bytes" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "a", io.readpartial(1)
        assert_equal "b", io.readpartial(1)
        assert_equal "c", io.readpartial(1)
      end

      it "reads maximum of one chunk" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "ab", io.readpartial(3)

        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "a", io.readpartial(1)
        assert_equal "b", io.readpartial(3)
      end

      it "returns empty string when length is zero" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "",    io.readpartial(0)
        assert_equal "abc", io.read
      end

      it "reads available data from cache" do
        io = chunked_io(chunks: ["abc"].each)
        io.readpartial(3)
        io.rewind
        assert_equal "a",  io.readpartial(1)
        assert_equal "bc", io.readpartial(2)
      end

      it "reads available data from cache and buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.readpartial(1)
        io.rewind
        assert_equal "ab", io.readpartial(4)
      end

      it "returns data in binary encoding" do
        io = chunked_io(chunks: ["ab", "c"])
        assert_equal Encoding::BINARY, io.readpartial(1).encoding
      end

      it "works with frozen chunks" do
        io = chunked_io(chunks: ["ab".freeze, "c".freeze])
        assert_equal Encoding::BINARY, io.readpartial(2).encoding
      end

      it "raises EOFError on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        assert_raises(EOFError) { io.readpartial(1) }
      end

      it "raises EOFError on zero chunks" do
        io = chunked_io(chunks: [].each)
        assert_raises(EOFError) { io.readpartial(1) }
      end
    end

    describe "with maxlen and buffer" do
      it "reads specified number of bytes" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "a", io.readpartial(1, "".dup)
        assert_equal "b", io.readpartial(1, "".dup)
        assert_equal "c", io.readpartial(1, "".dup)
      end

      it "reads maximum of one chunk" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "ab", io.readpartial(3, "".dup)
      end

      it "writes read content into the buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = "".dup
        io.readpartial(1, buffer)
        assert_equal "a", buffer
        io.readpartial(1, buffer)
        assert_equal "b", buffer
      end

      it "returns the buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = "".dup
        assert_equal buffer.object_id, io.readpartial(1, buffer).object_id
        assert_equal buffer.object_id, io.readpartial(2, buffer).object_id
        io.rewind
        assert_equal buffer.object_id, io.readpartial(1, buffer).object_id
        assert_equal buffer.object_id, io.readpartial(2, buffer).object_id
      end

      it "returns empty string when length is zero" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = "".dup
        assert_equal "",               io.readpartial(0, buffer)
        assert_equal buffer.object_id, io.readpartial(0, buffer).object_id
        assert_equal "abc", io.read
      end

      it "reads available data from cache" do
        io = chunked_io(chunks: ["abc"].each)
        io.readpartial(3, "".dup)
        io.rewind
        assert_equal "a",  io.readpartial(1, "".dup)
        assert_equal "bc", io.readpartial(2, "".dup)
      end

      it "reads available data from cache and buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.readpartial(1, "".dup)
        io.rewind
        assert_equal "ab", io.readpartial(4, "".dup)
      end

      it "returns data in the encoding of the buffer" do
        io = chunked_io(chunks: ["ab", "c"])
        assert_equal Encoding::UTF_8, io.readpartial(1, "".dup).encoding
        assert_equal Encoding::BINARY, io.readpartial(1, "".b).encoding
      end

      it "works with frozen chunks" do
        io = chunked_io(chunks: ["ab".freeze, "c".freeze])
        assert_equal "ab", io.readpartial(2, "".dup)
      end

      it "raises EOFError on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read
        buffer = "buffer".dup
        assert_raises(EOFError) { io.readpartial(1, buffer) }
        assert_equal "", buffer
      end

      it "raises EOFError on zero chunks" do
        io = chunked_io(chunks: [].each)
        buffer = "buffer".dup
        assert_raises(EOFError) { io.readpartial(1, buffer) }
        assert_equal "", buffer
      end
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.readpartial(4) }
    end

    it "raises ArgumentError on negative length" do
      io = chunked_io(chunks: ["ab", "c"].each)
      error = assert_raises(ArgumentError) { io.readpartial(-1) }
      assert_equal "negative length -1 given", error.message
    end

    it "reads cached content into a buffer with non-binary encoding" do
      io = chunked_io(chunks: ["\n\r\xC3\xA9--".b, "x\rcc\r\xC3".b, "\xA9\nc".b].each, encoding: "utf-8")
      io.gets(3)
      buffer = "garbage".dup
      assert_equal "\r\xC3\xA9--".dup.force_encoding("utf-8"), io.readpartial(5, buffer)
      assert_equal Encoding::UTF_8, buffer.encoding
    end

    it "keeps the buffer encoding at end of file" do
      io = chunked_io(chunks: ["ab"].each)
      io.read
      buffer = "garbage".dup
      assert_raises(EOFError) { io.readpartial(1, buffer) }
      assert_equal "", buffer
      assert_equal Encoding::UTF_8, buffer.encoding
    end

    it "skips empty chunks" do
      io = chunked_io(chunks: ["", "a", "", "", "b", ""].each)
      assert_equal "a", io.readpartial(10)
      assert_equal "b", io.readpartial(10)
      assert_raises(EOFError) { io.readpartial(10) }
    end
  end

  describe "reading" do
    it "downloads only how much it needs" do
      chunks = Enumerator.new do |y|
        y << "ab"
        y << "c"
        raise "never reached"
      end
      io = chunked_io(chunks: chunks)
      assert_equal "a", io.read(1)
      assert_equal "b", io.read(1)
    end

    it "updates #pos" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal 0, io.pos
      io.read(1)
      assert_equal 1, io.pos
      io.read
      assert_equal 3, io.pos
      io.rewind
      assert_equal 0, io.pos
      io.read(1)
      assert_equal 1, io.pos
      io.read
      assert_equal 3, io.pos
    end

    it "calls :on_close once whole content has been read" do
      on_close_called = nil
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { on_close_called = true })
      refute on_close_called
      io.read
      assert on_close_called
    end

    it "calls :on_close only once" do
      on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { on_close_called += 1 })
      io.read
      io.rewind
      io.read
      assert_equal 1, on_close_called
    end

    it "propagates exceptions that occur when retrieving chunks" do
      exceptional_chunks = Enumerator.new { |y| y << "content"; raise Timeout::Error }
      io = chunked_io(chunks: exceptional_chunks)
      assert_raises(Timeout::Error) { io.read }
    end

    it "calls enumerator's ensure block when chunk retrieval fails" do
      exceptional_chunks = Enumerator.new do |y|
        begin
          y << "content"
          raise Timeout::Error
        ensure
          @ensure_called = true
        end
      end
      io = chunked_io(chunks: exceptional_chunks)
      io.read rescue nil
      assert @ensure_called
    end

    it "calls :on_close when chunk retrieval fails" do
      exceptional_chunks = Enumerator.new do |y|
        y << "content"
        raise Timeout::Error
      end
      on_close_called = nil
      io = chunked_io(chunks: exceptional_chunks, on_close: -> { on_close_called = true })
      io.read rescue nil
      assert on_close_called
    end
  end

  describe "#each_chunk" do
    it "yields chunks with a block" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.each_chunk { |chunk| (@chunks ||= []) << chunk }
      assert_equal ["ab", "c"], @chunks
    end

    it "returns an enumerator without a block" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal ["ab", "c"], io.each_chunk.to_a
    end

    it "doesn't cache retrieved chunks" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.each_chunk {}
      io.rewind
      assert_equal "", io.read
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.each_chunk {} }
    end
  end

  describe "#seek" do
    describe "default" do
      it "moves to absolute position" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.seek(1)
        assert_equal 1,    io.tell
        assert_equal "bc", io.read
      end
    end

    describe "SET" do
      it "moves to absolute position" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.seek(2)
        assert_equal 2,   io.tell
        assert_equal "c", io.read
      end
    end

    describe "CUR" do
      it "moves to relative position" do
        io = chunked_io(chunks: ["ab", "cd"].each)
        io.seek(1, IO::SEEK_CUR)
        assert_equal 1, io.tell
        io.seek(2, IO::SEEK_CUR)
        assert_equal 3,   io.tell
        assert_equal "d", io.read
      end
    end

    describe "END" do
      it "moves to position from end" do
        io = chunked_io(chunks: ["ab", "cd"].each)
        io.seek(-2, IO::SEEK_END)
        assert_equal 2,    io.tell
        assert_equal "cd", io.read
      end
    end

    it "seeks uncached content" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.seek(1)
      assert_equal 1, io.tell
      assert_equal "bc", io.read
    end

    it "seeks cached content" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(1)
      io.rewind
      io.seek(1)
      assert_equal 1, io.tell
      assert_equal "bc", io.read
    end

    it "seeks cached and uncached content" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(1)
      io.rewind
      io.seek(2)
      assert_equal 2, io.tell
      assert_equal "c", io.read
    end

    it "raises error on invalid whence" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(1)
      assert_raises ArgumentError do
        io.seek(2, :invalid)
      end
    end

    it "returns 0" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal 0, io.seek(2)
      assert_equal 0, io.seek(-1, :CUR)
      assert_equal 0, io.seek(-1, :END)
    end

    it "allows seeking beyond end of file" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.seek(10)
      assert_equal 10, io.pos
      assert_equal true, io.eof?
      assert_equal "", io.read
      assert_nil io.read(1)
      io.seek(1)
      assert_equal "bc", io.read
    end

    it "keeps the position when seeking before start of file" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(1)
      assert_raises(Errno::EINVAL) { io.seek(-4, :END) }
      assert_equal 1, io.pos
      assert_equal "bc", io.read
    end

    it "accounts for content not yet read when seeking from end" do
      io = chunked_io(chunks: ["abc"].each)
      io.read(1)
      io.seek(-1, :END)
      assert_equal "c", io.read
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.seek(0) }
    end

    it "raises Errno::ESPIPE when not rewindable" do
      io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
      error = assert_raises(Errno::ESPIPE) { io.seek(0) }
      assert_equal "Illegal seek", error.message
    end
  end

  describe "#pos" do
    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.pos }
    end
  end

  describe "#eof?" do
    it "returns false on nonzero chunks" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal false, io.eof?
    end

    it "returns true on zero chunks" do
      io = chunked_io(chunks: [].each)
      assert_equal true, io.eof?
    end

    it "returns true when all data has been read" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read
      assert_equal true, io.eof?
    end

    it "returns false when there is still data to be read" do
      io = chunked_io(chunks: ["ab", "cd"].each)
      io.read(1)
      assert_equal false, io.eof?
      io.read(2)
      assert_equal false, io.eof?
    end

    it "returns false when on end of tempfile and there is still data to be read" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(2)
      assert_equal false, io.eof?
    end

    it "returns false when not on end of tempfile and there is no more data to be read" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read
      io.rewind
      assert_equal false, io.eof?
    end

    it "returns false when not on end of tempfile and there is still data to be read" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(2)
      io.rewind
      assert_equal false, io.eof?
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.eof? }
    end

    it "returns true when remaining chunks are empty" do
      io = chunked_io(chunks: ["ab", "", ""].each)
      io.read(2)
      assert_equal true, io.eof?
      assert_equal true, chunked_io(chunks: ["", ""].each).eof?
    end
  end

  describe "#rewind" do
    it "rewinds the IO if it's rewindable" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal "abc", io.read
      io.rewind
      assert_equal "abc", io.read
    end

    it "raises an error if IO is not rewindable" do
      io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
      assert_equal "abc", io.read
      assert_raises(IOError) { io.rewind }
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.rewind }
    end
  end

  describe "#close" do
    it "calls :on_close" do
      on_close_called = nil
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { on_close_called = true })
      io.close
      assert on_close_called
    end

    it "doesn't call :on_close again after whole content has been read" do
      on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { on_close_called += 1 })
      io.read
      io.close
      assert_equal 1, on_close_called
    end

    it "doesn't fail when :on_close wasn't specified" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
    end

    it "calls enumerator's ensure block" do
      chunks = Enumerator.new do |y|
        begin
          y << "ab"
          y << "c"
        ensure
          @ensure_called = true
        end
      end
      io = chunked_io(chunks: chunks)
      io.close
      assert @ensure_called
    end

    it "doesn't error when called after #each_chunk" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.each_chunk {}
      io.close
    end

    it "can be called multiple times" do
      on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { on_close_called += 1 })
      io.close
      io.close
      assert_equal 1, on_close_called
    end
  end

  describe "#closed?" do
    it "returns false when #close was not called" do
      io = chunked_io(chunks: [].each)
      assert_equal false, io.closed?
    end

    it "returns truen when #close was called" do
      io = chunked_io(chunks: [].each)
      io.close
      assert_equal true, io.closed?
    end
  end

  describe "#rewindable?" do
    it "returns true by default" do
      io = chunked_io(chunks: [].each)
      assert_equal true, io.rewindable?
    end

    it "returns false if :rewindable is false" do
      io = chunked_io(chunks: [].each, rewindable: false)
      assert_equal false, io.rewindable?
    end
  end

  describe "#inspect" do
    it "shows important information" do
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=nil encoding=#{Encoding::BINARY.inspect} data={} on_close=nil rewindable=true>",
                   chunked_io(chunks: [""].each).inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=10 encoding=#{Encoding::BINARY.inspect} data={} on_close=nil rewindable=true>",
                   chunked_io(chunks: [""].each, size: 10).inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=nil encoding=#{Encoding::UTF_8.inspect} data={} on_close=nil rewindable=true>",
                   chunked_io(chunks: [""].each, encoding: "utf-8").inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=nil encoding=#{Encoding::BINARY.inspect} data=#{{ foo: "bar" }.inspect} on_close=nil rewindable=true>",
                   chunked_io(chunks: [""].each, data: {foo: "bar"}).inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"a\"]:each> size=nil encoding=#{Encoding::BINARY.inspect} data={} on_close=:callable rewindable=true>",
                   chunked_io(chunks: ["a"].each, on_close: :callable).inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=nil encoding=#{Encoding::BINARY.inspect} data={} on_close=nil rewindable=false>",
                   chunked_io(chunks: [""].each, rewindable: false).inspect
      assert_equal "#<Down::ChunkedIO chunks=#<Enumerator: [\"\"]:each> size=nil encoding=#{Encoding::BINARY.inspect} data={} on_close=nil rewindable=true (closed)>",
                   chunked_io(chunks: [""].each).tap(&:close).inspect
    end
  end

  it "can be parsed by the CSV standard library" do
    require "csv"
    io = chunked_io(chunks: ["h1,h2,h3\na", ",b,c\nd,", "e,f\ng,h,i"])
    rows = CSV.parse(io, headers: true)
    assert_equal Hash["h1"=>"a", "h2"=>"b", "h3"=>"c"], rows[0].to_h
    assert_equal Hash["h1"=>"d", "h2"=>"e", "h3"=>"f"], rows[1].to_h
    assert_equal Hash["h1"=>"g", "h2"=>"h", "h3"=>"i"], rows[2].to_h
  end

  describe "parity with IO" do
    CONTENT = "\n\nhéllo\r\nwörld--€\n\n\n\npara two\nline--x--y€z\r\n\nend\n"

    # Returns a native IO with the given content as the reference.
    def native_io(content, encoding)
      file = Tempfile.new("down-chunked_io-test", binmode: true)
      file.write(content.b)
      file.rewind
      file.set_encoding(encoding, encoding)
      file
    end

    def assert_same_string(expected, actual, message)
      if expected.nil?
        assert_nil actual, message
      else
        assert_equal expected, actual, message
        assert_equal expected.encoding, actual.encoding, message
      end
    end

    def sliced_io(content, slice_size, **options)
      chunks = content.b.each_char.each_slice(slice_size).map(&:join)
      chunked_io(chunks: chunks.each, **options)
    end

    [true, false].each do |rewindable|
      describe rewindable ? "when rewindable" : "when not rewindable" do
        [[], ["\n"], ["--"], ["\r\n"], [""], [nil], [1], [3], [-1], ["\n", 4],
         ["--", 2], ["", 5], [nil, 2]].each do |args|
          [false, true].each do |chomp|
            it "returns the same lines from #gets(#{args.map(&:inspect).join(", ")}, chomp: #{chomp})" do
              [Encoding::UTF_8, Encoding::BINARY].each do |encoding|
                [1, 2, 3, 7, 100].each do |slice_size|
                  native = native_io(CONTENT, encoding)
                  io     = sliced_io(CONTENT, slice_size, encoding: encoding, rewindable: rewindable)

                  loop do
                    expected = native.gets(*args, chomp: chomp)
                    actual   = io.gets(*args, chomp: chomp)
                    message  = "encoding=#{encoding}, slice_size=#{slice_size}"

                    assert_same_string expected, actual, message
                    assert_equal native.pos, io.pos, message
                    assert_equal native.eof?, io.eof?, message

                    break if expected.nil?
                  end
                end
              end
            end
          end
        end

        [[1], [2], [5], [nil], [3, "".dup], [4, "".b], [nil, "".dup]].each do |args|
          it "returns the same content from #read(#{args.map(&:inspect).join(", ")})" do
            [Encoding::UTF_8, Encoding::BINARY].each do |encoding|
              [1, 3, 100].each do |slice_size|
                native = native_io(CONTENT, encoding)
                io     = sliced_io(CONTENT, slice_size, encoding: encoding, rewindable: rewindable)

                loop do
                  expected = native.read(*args.map { |arg| arg.dup })
                  actual   = io.read(*args.map { |arg| arg.dup })
                  message  = "encoding=#{encoding}, slice_size=#{slice_size}"

                  assert_same_string expected, actual, message
                  assert_equal native.pos, io.pos, message

                  break if expected.nil? || expected.empty?
                end
              end
            end
          end
        end
      end
    end
  end

  describe "content retrieval" do
    it "doesn't retrieve more chunks when a line ends at a chunk boundary" do
      chunks = Enumerator.new do |y|
        y << "a\n"
        y << "b\n"
        raise "never reached"
      end
      io = chunked_io(chunks: chunks)
      assert_equal "a\n", io.gets
    end

    it "retrieves more chunks when a line limit cuts a multibyte character" do
      io = chunked_io(chunks: ["a\xC3".b, "\xA9b".b].each, encoding: "utf-8")
      assert_equal "aé", io.gets(2)
      assert_equal "b",  io.gets
    end

    it "returns an incomplete multibyte character cut by the limit at end of file" do
      [true, false].each do |rewindable|
        io = chunked_io(chunks: ["-\xE2".b, "\x82".b].each, encoding: "utf-8", rewindable: rewindable)
        assert_equal "-\xE2\x82".b, io.gets(nil, 2).b
        assert_nil io.gets
      end
    end

    it "reads lines spanning many chunks" do
      io = chunked_io(chunks: (["a"] * 10_000 + ["\nb"]).each)
      assert_equal "a" * 10_000 + "\n", io.gets
      assert_equal "b", io.gets
    end
  end

  describe "when not rewindable" do
    it "discards read content while keeping the position" do
      chunk = "a" * 50_000 + "\n"
      io = chunked_io(chunks: [chunk, chunk, chunk].each, rewindable: false)
      assert_equal chunk * 2, io.read(chunk.bytesize * 2)
      assert_equal chunk.bytesize * 2, io.pos
      assert_equal chunk, io.gets
      assert_equal chunk.bytesize * 3, io.pos
      assert_equal chunk.bytesize, io.send(:store).string.bytesize
      assert_equal true, io.eof?
    end
  end

  it "doesn't modify retrieved chunks" do
    [true, false].each do |rewindable|
      chunks = ["ab\n".b, "cd\nef".b, "\ngh".b]
      originals = chunks.map(&:dup)
      io = chunked_io(chunks: chunks.each, encoding: "utf-8", rewindable: rewindable)
      nil while io.gets
      assert_equal originals, chunks
      assert_equal [Encoding::BINARY] * 3, chunks.map(&:encoding)
    end
  end

  describe "#encoding=" do
    it "changes the encoding of read content" do
      io = chunked_io(chunks: ["ab\n", "cd"].each)
      assert_equal Encoding::BINARY, io.gets.encoding
      io.encoding = "utf-8"
      assert_equal Encoding::UTF_8, io.encoding
      assert_equal Encoding::UTF_8, io.read.encoding
    end

    it "falls back to binary encoding" do
      io = chunked_io(chunks: ["ab"].each, encoding: "utf-8")
      io.encoding = "unknown"
      assert_equal Encoding::BINARY, io.encoding
      assert_equal Encoding::BINARY, io.read.encoding
    end
  end

  it "doesn't transcode to the default internal encoding" do
    [true, false].each do |rewindable|
      io = chunked_io(chunks: ["é\n".b].each, encoding: "utf-8", rewindable: rewindable)
      original_internal, original_verbose = Encoding.default_internal, $VERBOSE
      begin
        $VERBOSE = nil # silence warning about setting default internal encoding
        Encoding.default_internal = Encoding::ISO_8859_1
        assert_equal "é\n", io.gets
      ensure
        Encoding.default_internal = original_internal
        $VERBOSE = original_verbose
      end
    end
  end

  it "caches content into an anonymous tempfile" do
    io = chunked_io(chunks: ["ab"].each)
    io.read
    tempfile = io.send(:store)
    assert_kind_of File, tempfile
    assert_equal false, File.file?(tempfile.path)
    assert_equal true, tempfile.binmode?
    io.close
    assert_equal true, tempfile.closed?
  end
end
