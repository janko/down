require "test_helper"
require "down/chunked_io"
require "timeout"

describe Down::ChunkedIO do
  def chunked_io(options = {})
    Down::ChunkedIO.new(options)
  end

  describe "initializing" do
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
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "abc", io.read
      end

      it "reads remaining content" do
        io = chunked_io(chunks: ["ab", "c"].each)
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

      it "handles zero chunks" do
        io = chunked_io(chunks: [].each)
        assert_equal "", io.read
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        io.read(1)
        assert_equal "bc", io.read
      end

      it "returns content in correct encoding" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal Encoding::BINARY, io.read.encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read.encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::UTF_8, io.read.encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read.encoding
      end

      it "doesn't use #size" do
        io = chunked_io(chunks: ["ab", "c"].each, size: :bogus)
        io.read(1)
        assert_equal "bc", io.read
      end
    end

    describe "with length" do
      it "reads partial content" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end

      it "reads as much as it can read" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal "abc", io.read(4)
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
        io.read(3)
        assert_nil io.read(1)
      end

      it "handles zero chunks" do
        io = chunked_io(chunks: [].each)
        assert_nil io.read(1)
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end

      it "returns content in correct encoding" do
        io = chunked_io(chunks: ["ab", "c"].each)
        assert_equal Encoding::BINARY, io.read(1).encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read(1).encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::UTF_8, io.read(1).encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read(1).encoding
      end

      it "doesn't use #size" do
        io = chunked_io(chunks: ["ab", "c"].each, size: :bogus)
        assert_equal "a",  io.read(1)
        assert_equal "bc", io.read(2)
      end
    end

    describe "with length and buffer" do
      it "reads partial content into the buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = ""
        io.read(1, buffer)
        assert_equal "a", buffer
        io.read(2, buffer)
        assert_equal "bc", buffer
      end

      it "returns the given buffer" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = ""
        assert_equal buffer.object_id, io.read(1, buffer).object_id
        assert_equal buffer.object_id, io.read(2, buffer).object_id
        io.rewind
        assert_equal buffer.object_id, io.read(1, buffer).object_id
        assert_equal buffer.object_id, io.read(2, buffer).object_id
      end

      it "reads as much as it can read" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = ""
        io.read(4, buffer)
        assert_equal "abc", buffer
      end

      it "reads from cache" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1)
        io.rewind
        buffer = ""
        io.read(1, buffer)
        assert_equal "a", buffer
        io.read(2, buffer)
        assert_equal "bc", buffer
      end

      it "seamlessly switches between reading cached and new content" do
        io = chunked_io(chunks: ["ab", "c"].each)
        io.read(1)
        io.rewind
        buffer = ""
        io.read(3, buffer)
        assert_equal "abc", buffer
      end

      it "returns nil on eof" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = ""
        io.read(3, buffer)
        assert_nil io.read(1, buffer)
        assert_equal "", buffer
      end

      it "handles zero chunks" do
        io = chunked_io(chunks: [].each)
        buffer = "buffer"
        assert_nil io.read(1, buffer)
        assert_equal "", buffer
      end

      it "works when not rewindable" do
        io = chunked_io(chunks: ["ab", "c"].each, rewindable: false)
        buffer = ""
        io.read(1, buffer)
        assert_equal "a", buffer
        io.read(2, buffer)
        assert_equal "bc", buffer
      end

      it "returns content in correct encoding" do
        io = chunked_io(chunks: ["ab", "c"].each)
        buffer = ""
        assert_equal Encoding::BINARY, io.read(1, buffer).encoding
        io.rewind
        assert_equal Encoding::BINARY, io.read(1, buffer).encoding

        io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
        assert_equal Encoding::UTF_8, io.read(1, buffer).encoding
        io.rewind
        assert_equal Encoding::UTF_8, io.read(1, buffer).encoding
      end

      it "doesn't use #size" do
        io = chunked_io(chunks: ["ab", "c"].each, size: :bogus)
        buffer = ""
        io.read(1, buffer)
        assert_equal "a", buffer
        io.read(2, buffer)
        assert_equal "bc", buffer
      end
    end

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

    it "calls :on_close once whole content has been read" do
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { @on_close_called = true })
      refute @on_close_called
      io.read
      assert @on_close_called
    end

    it "calls :on_close only once" do
      @on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { @on_close_called += 1 })
      io.read
      io.rewind
      io.read
      assert_equal 1, @on_close_called
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.read }
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
      io = chunked_io(chunks: exceptional_chunks, on_close: -> { @on_close_called = true })
      io.read rescue nil
      assert @on_close_called
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

    it "returns chunks in correct encoding" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.each_chunk { |chunk| assert_equal Encoding::BINARY, chunk.encoding }

      io = chunked_io(chunks: ["ab", "c"].each, encoding: "utf-8")
      io.each_chunk { |chunk| assert_equal Encoding::UTF_8, chunk.encoding }
    end

    it "raises IOError when closed" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.close
      assert_raises(IOError) { io.each_chunk {} }
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
      io = chunked_io(chunks: ["ab", "c"])
      io.read
      assert_equal true, io.eof?
    end

    it "returns false when there is still data to be read" do
      io = chunked_io(chunks: ["ab", "cd"])
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
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { @on_close_called = true })
      io.close
      assert @on_close_called
    end

    it "doesn't call :on_close again after whole content has been read" do
      @on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { @on_close_called += 1 })
      io.read
      io.close
      assert_equal 1, @on_close_called
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
      @on_close_called = 0
      io = chunked_io(chunks: ["ab", "c"].each, on_close: -> { @on_close_called += 1 })
      io.close
      io.close
      assert_equal 1, @on_close_called
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
end
