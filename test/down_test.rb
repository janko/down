require "test_helper"
require "stringio"

describe Down do
  describe "#download" do
    it "downloads url to disk" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_instance_of Tempfile, tempfile
      assert File.exist?(tempfile.path)
    end

    it "works with query parameters" do
      stub_request(:get, "http://example.com/image.jpg?foo=bar")
      Down.download("http://example.com/image.jpg?foo=bar")
    end

    it "converts small StringIOs to tempfiles" do
      stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/small.jpg")
      assert_instance_of Tempfile, tempfile
      assert File.exist?(tempfile.path)
      assert_equal "aaaaa", tempfile.read
    end

    it "accepts max size" do
      # "Content-Length" header
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      assert_raises(Down::TooLarge) { Down.download("http://example.com/image.jpg", max_size: 4) }

      # no "Content-Length" header
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      assert_raises(Down::TooLarge) { Down.download("http://example.com/image.jpg", max_size: 4) }

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      tempfile = Down.download("http://example.com/image.jpg", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "accepts :progress_proc and :content_length_proc" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      Down.download "http://example.com/image.jpg",
        content_length_proc: ->(n) { @content_length = n },
        progress_proc:       ->(n) { @progress = n }
      assert_equal 5, @content_length
      assert_equal 5, @progress
    end

    it "makes downloaded files have original_filename and content_type" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024, headers: {'Content-Type' => 'image/jpeg'})
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "image.jpg", tempfile.original_filename
      assert_equal "image/jpeg", tempfile.content_type

      stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5, headers: {'Content-Type' => 'image/jpeg'})
      tempfile = Down.download("http://example.com/small.jpg")
      assert_equal "small.jpg", tempfile.original_filename
      assert_equal "image/jpeg", tempfile.content_type
    end

    it "decodes the original filename" do
      stub_request(:get, "http://example.com/image%20space%2Fslash.jpg").to_return(body: "a" * 20 * 1024)
      tempfile = Down.download("http://example.com/image%20space%2Fslash.jpg")
      assert_equal "image space/slash.jpg", tempfile.original_filename
    end

    it "makes original filename return nil when path is missing" do
      stub_request(:get, "http://example.com").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com")
      assert_equal nil, tempfile.original_filename

      stub_request(:get, "http://example.com/").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/")
      assert_equal nil, tempfile.original_filename
    end

    it "fetches original filename from Content-Disposition if it's available" do
      stub_request(:get, "http://example.com/image.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'filename="myfilename.foo"'})

      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "myfilename.foo", tempfile.original_filename
    end

    it "fetches original filename from Content-Disposition without quotes if it's available" do
      stub_request(:get, "http://example.com/image.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'attachment; filename=myfilename.foo '})

      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "myfilename.foo", tempfile.original_filename
    end

    it "follows redirects" do
      stub_request(:get, "http://example.com").to_return(status: 301, headers: {'Location' => 'http://example1.com'})
      stub_request(:get, "http://example1.com").to_return(status: 301, headers: {'Location' => 'http://example2.com'})

      stub_request(:get, "http://example2.com").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com")
      assert_equal "aaaaa", tempfile.read

      stub_request(:get, "http://example2.com").to_return(status: 301, headers: {'Location' => 'http://example3.com'})
      assert_raises(Down::NotFound) { Down.download("http://example.com") }

      stub_request(:get, "http://example3.com").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com", max_redirects: 3)
      assert_equal "aaaaa", tempfile.read
    end

    it "preserves extension" do
      # Tempfile
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal ".jpg", File.extname(tempfile.path)
      assert File.exist?(tempfile.path)

      # StringIO
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal ".jpg", File.extname(tempfile.path)
      assert File.exist?(tempfile.path)
    end

    it "automatically applies basic authentication" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5) if ENV["CI"]
      stub_request(:get, "http://user:password@example.com/image.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://user:password@example.com/image.jpg")
      assert_equal "aaaaa", tempfile.read
    end

    it "forwards options to open-uri" do
      stub_request(:get, "http://example.com").to_return(status: 301, headers: {'Location' => 'http://example2.com'})
      stub_request(:get, "http://example2.com").to_return(body: "redirected")
      tempfile = Down.download("http://example.com", redirect: true)
      assert_equal "redirected", tempfile.read
    end

    it "raises NotFound on HTTP errors" do
      stub_request(:get, "http://example.com").to_return(status: 404)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }

      stub_request(:get, "http://example.com").to_return(status: 500)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }
    end

    it "raises on invalid URL" do
      assert_raises(Down::Error) { Down.download("http:\\example.com/image.jpg") }
    end

    it "raises on invalid scheme" do
      assert_raises(Down::Error) { Down.download("foo://example.com/image.jpg") }
    end

    it "doesn't allow shell execution" do
      assert_raises(Down::Error) { Down.download("| ls") }
    end
  end

  describe "#stream" do
    it "calls the block with downloaded chunks" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => '5'})
      chunks = Down.enum_for(:stream, "http://example.com/image.jpg").to_a
      refute_empty chunks
      assert_equal "aaaaa", chunks.map(&:first).join
      assert_equal 5, chunks.first.last
    end

    it "yields nil for content length if header is not present" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      chunks = Down.enum_for(:stream, "http://example.com/image.jpg").to_a
      assert_equal nil, chunks.first.last
    end

    it "handles HTTPS links" do
      stub_request(:get, "https://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => '5'})
      chunks = Down.enum_for(:stream, "https://example.com/image.jpg").to_a
      refute_empty chunks
      assert_equal "aaaaa", chunks.map(&:first).join
      assert_equal 5, chunks.first.last
    end
  end

  describe "#open" do
    it "assigns chunks from response body" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      assert_equal "abc", io.read
    end

    it "works with query parameters" do
      stub_request(:get, "http://example.com/image.jpg?foo=bar")
      Down.open("http://example.com/image.jpg?foo=bar")
    end

    it "extracts size from Content-Length" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 3, io.size

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      assert_equal nil, io.size
    end

    it "works around chunked Transfer-Encoding response" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Transfer-Encoding' => 'chunked'})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 3, io.size
      assert_equal "abc", io.read
    end

    it "closes connection on #close" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      Net::HTTP.any_instance.expects(:do_finish)
      io.close
    end
  end

  describe "#copy_to_tempfile" do
    it "returns a tempfile" do
      tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))
      assert_instance_of Tempfile, tempfile
    end

    it "rewinds IOs" do
      io = StringIO.new("foo")
      tempfile = Down.copy_to_tempfile("foo", io)
      assert_equal "foo", io.read
      assert_equal "foo", tempfile.read
    end

    it "opens in binmode" do
      tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))
      assert tempfile.binmode?
    end

    it "accepts basenames to be nested paths" do
      tempfile = Down.copy_to_tempfile("foo/bar/baz", StringIO.new("foo"))
      assert File.exist?(tempfile.path)
    end

    it "preserves extension" do
      tempfile = Down.copy_to_tempfile("foo.jpg", StringIO.new("foo"))
      assert_equal ".jpg", File.extname(tempfile.path)
    end
  end
end

describe Down::ChunkedIO do
  def chunked_io(options = {})
    defaults = {chunks: ["ab", "c"].each, size: 3, on_close: ->{}}
    Down::ChunkedIO.new(defaults.merge(options))
  end

  describe "#size" do
    it "returns the given size" do
      io = chunked_io(size: 3)
      assert_equal 3, io.size
    end
  end

  describe "#read" do
    it "returns contents of the file without arguments" do
      io = chunked_io(chunks: ["abc"].each)
      assert_equal "abc", io.read
    end

    it "accepts length" do
      io = chunked_io(chunks: ["abc"].each)
      assert_equal "a",  io.read(1)
      assert_equal "bc", io.read(2)
    end

    it "accepts buffer" do
      io = chunked_io(chunks: ["abc"].each)
      buffer = ""
      io.read(2, buffer)
      assert_equal "ab", buffer
      io.read(1, buffer)
      assert_equal "c", buffer
    end

    it "downloads only how much it needs" do
      io = chunked_io(chunks: ["ab", "c"].each)
      assert_equal 0, io.tempfile.size
      io.read(1)
      assert_equal 2, io.tempfile.size
      io.read(1)
      assert_equal 2, io.tempfile.size
      io.read(1)
      assert_equal 3, io.tempfile.size
    end

    it "calls :on_close callback after everything is read" do
      io = chunked_io(on_close: (on_close = ->{}))
      on_close.expects(:call)
      io.read
    end

    it "calls :on_close only once" do
      io = chunked_io(on_close: (on_close = ->{}))
      on_close.expects(:call).once
      io.read
      io.rewind
      io.read
    end
  end

  describe "#each_chunk" do
    it "yields chunks" do
      io = chunked_io(chunks: ["a", "b", "c"].each)
      io.each_chunk { |chunk| (@chunks ||= []) << chunk }
      assert_equal ["a", "b", "c"], @chunks
    end

    it "returns an enumerator without arguments" do
      io = chunked_io(chunks: ["a", "b", "c"].each)
      assert_equal ["a", "b", "c"], io.each_chunk.to_a
    end

    it "calls :on_close callback after yielding chunks" do
      io = chunked_io(chunks: ["abc"].each, on_close: (on_close = ->{}))
      on_close.expects(:call)
      io.each_chunk {}
    end

    it "calls :on_close only once" do
      io = chunked_io(chunks: ["abc"].each, on_close: (on_close = ->{}))
      on_close.expects(:call).once
      io.each_chunk {}
      io.each_chunk {}
    end
  end

  describe "#eof?" do
    it "returns true when the whole file is read" do
      io = chunked_io
      assert_equal false, io.eof?
      io.read
      assert_equal true, io.eof?
    end

    it "returns false when on end of tempfile, but not on end of download" do
      io = chunked_io(chunks: ["ab", "c"].each)
      io.read(2)
      assert_equal true,  io.tempfile.eof?
      assert_equal false, io.eof?
      io.read(1)
      assert_equal true, io.eof?
    end

    it "returns true when on end of file and on last chunk" do
      io = chunked_io
      assert_equal false, io.eof?
      io.read(io.size)
      assert_equal true, io.eof?
    end
  end

  describe "#rewind" do
    it "rewinds the file" do
      io = chunked_io(chunks: ["abc"].each)
      assert_equal "abc", io.read
      io.rewind
      assert_equal "abc", io.read
    end
  end

  describe "#close" do
    it "deletes the underlying tempfile" do
      io = chunked_io
      path = io.tempfile.path
      io.close
      refute File.exists?(path)
    end

    it "calls :on_close" do
      io = chunked_io(on_close: (on_close = ->{}))
      on_close.expects(:call)
      io.close
    end

    it "doesn't error when called after #each_chunk" do
      io = chunked_io
      io.each_chunk {}
      io.close
    end
  end

  it "works without :size" do
    io = chunked_io(size: nil, chunks: ["a", "b", "c"].each)
    assert_equal nil, io.size
    io.read(1)
    assert_equal false, io.eof?
    io.read(1)
    assert_equal false, io.eof?
    io.rewind
    io.read
    assert_equal true, io.eof?
  end
end
