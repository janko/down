require "test_helper"

require "down"

require "stringio"
require "json"
require "base64"

describe Down do
  describe "#download" do
    it "downloads content" do
      tempfile = Down.download("#{$httpbin}/bytes/#{20*1024}?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/#{20*1024}?seed=0").to_s, tempfile.read

      tempfile = Down.download("#{$httpbin}/bytes/#{1024}?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/#{1024}?seed=0").to_s, tempfile.read
    end

    it "returns a Tempfile" do
      tempfile = Down.download("#{$httpbin}/bytes/#{20*1024}")
      assert_instance_of Tempfile, tempfile

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down.download("#{$httpbin}/bytes/#{1024}")
      assert_instance_of Tempfile, tempfile
    end

    it "saves Tempfile to disk" do
      tempfile = Down.download("#{$httpbin}/bytes/#{20*1024}")
      assert File.exist?(tempfile.path)

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down.download("#{$httpbin}/bytes/#{1024}")
      assert File.exist?(tempfile.path)
    end

    it "opens the Tempfile in binary mode" do
      tempfile = Down.download("#{$httpbin}/bytes/#{20*1024}")
      assert tempfile.binmode?

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down.download("#{$httpbin}/bytes/#{1024}")
      assert tempfile.binmode?
    end

    it "gives the Tempfile a file extension" do
      tempfile = Down.download("#{$httpbin}/robots.txt")
      assert_match /\.txt$/, tempfile.path
    end

    it "accepts an URI object" do
      tempfile = Down.download(URI("#{$httpbin}/bytes/100"))
      assert_equal 100, tempfile.size
    end

    it "uses a default User-Agent" do
      tempfile = Down.download("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(tempfile.read)["user-agent"]

      tempfile = Down.download("#{$httpbin}/user-agent", {"User-Agent" => "Custom/Agent"})
      assert_equal "Custom/Agent", JSON.parse(tempfile.read)["user-agent"]
    end

    it "accepts max size" do
      assert_raises(Down::TooLarge) do
        Down.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4)
      end
      assert_raises(Down::TooLarge) do
        Down.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4, content_length_proc: ->(n){})
      end

      assert_raises(Down::TooLarge) do
        Down.download("#{$httpbin}/stream-bytes/100", max_size: 50)
      end
      assert_raises(Down::TooLarge) do
        Down.download("#{$httpbin}/stream-bytes/100", max_size: 50, progress_proc: ->(n){})
      end

      tempfile = Down.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "accepts content length proc" do
      Down.download "#{$httpbin}/response-headers?Content-Length=10",
        content_length_proc: ->(n) { @content_length = n }

      assert_equal 10, @content_length
    end

    it "accepts progress proc" do
      Down.download "#{$httpbin}/stream-bytes/100?chunk_size=10",
        progress_proc: ->(n) { (@progress ||= []) << n }

      assert_equal [10, 20, 30, 40, 50, 60, 70, 80, 90, 100], @progress
    end

    it "detects and applies basic authentication from URL" do
      tempfile = Down.download("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "follows redirects" do
      tempfile = Down.download("#{$httpbin}/redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down.download("#{$httpbin}/redirect/2")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      error = assert_raises(Down::Error) { Down.download("#{$httpbin}/redirect/3") }
      assert_equal "too many redirects", error.message

      tempfile = Down.download("#{$httpbin}/redirect/3", max_redirects: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      error = assert_raises(Down::Error) { Down.download("#{$httpbin}/redirect/4", max_redirects: 3) }
      assert_equal "too many redirects", error.message

      tempfile = Down.download("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down.download("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
    end

    # I don't know how to test that the proxy is actually used
    it "accepts proxy" do
      tempfile = Down.download("#{$httpbin}/bytes/100", proxy: $httpbin)
      assert_equal 100, tempfile.size

      tempfile = Down.download("#{$httpbin}/bytes/100", proxy: $httpbin.sub("http://", '\0user:password@'))
      assert_equal 100, tempfile.size

      tempfile = Down.download("#{$httpbin}/bytes/100", proxy: URI($httpbin.sub("http://", '\0user:password@')))
      assert_equal 100, tempfile.size
    end

    it "forwards other options to open-uri" do
      tempfile = Down.download("#{$httpbin}/basic-auth/user/password", http_basic_authentication: ["user", "password"])
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]

      tempfile = Down.download("#{$httpbin}/basic-auth/user/password", {"Authorization" => "Basic #{Base64.encode64("user:password")}"})
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "adds #content_type extracted from Content-Type" do
      tempfile = Down.download("#{$httpbin}/image/png")
      assert_equal "image/png", tempfile.content_type

      # We also want to test scenario when Content-Type is blank, but httpbin
      # doesn't seem to have such an endpoint, and /response-headers appends
      # the given Content-Type onto the default "application/json".
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%20filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%2520filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=myfilename.ext ")
      assert_equal "myfilename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      tempfile = Down.download("#{$httpbin}/robots.txt")
      assert_equal "robots.txt", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/basic-auth/user/pass%20word", http_basic_authentication: ["user", "pass word"])
      assert_equal "pass word", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"\"")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down.download("#{$httpbin}/")
      assert_nil tempfile.original_filename

      tempfile = Down.download("#{$httpbin}")
      assert_nil tempfile.original_filename
    end

    it "raises NotFound on HTTP error responses" do
      assert_raises(Down::NotFound) { Down.download("#{$httpbin}/status/400") }
      assert_raises(Down::NotFound) { Down.download("#{$httpbin}/status/500") }
    end

    it "raises NotFound on invalid URL" do
      assert_raises(Down::NotFound) { Down.download("http:\\example.org") }
      assert_raises(Down::NotFound) { Down.download("http:/example.org") }
      assert_raises(Down::NotFound) { Down.download("foo:/example.org") }
      assert_raises(Down::NotFound) { Down.download("#{$httpbin}/get", read_timeout: 0) }
    end

    it "doesn't allow shell execution" do
      assert_raises(Down::Error) { Down.download("| ls") }
    end
  end

  describe "#open" do
    it "streams response body in chunks" do
      io = Down.open("#{$httpbin}/stream/10")
      assert_equal 10, io.each_chunk.count
    end

    it "accepts an URI object" do
      io = Down.open(URI("#{$httpbin}/stream/10"))
      assert_equal 10, io.each_chunk.count
    end

    it "downloads on demand" do
      start = Time.now
      io = Down.open("#{$httpbin}/drip?duration=1&delay=0")
      io.close
      assert_operator Time.now - start, :<, 1
    end

    it "extracts size from Content-Length" do
      io = Down.open(URI("#{$httpbin}/bytes/100"))
      assert_equal 100, io.size

      io = Down.open(URI("#{$httpbin}/stream-bytes/100"))
      assert_nil io.size
    end

    it "responds to #close" do
      io = Down.open("#{$httpbin}/bytes/100")
      io.close
    end

    it "accepts request headers" do
      io = Down.open("#{$httpbin}/headers", {"Key" => "Value"})
      assert_equal "Value", JSON.parse(io.read)["headers"]["Key"]
    end

    # I don't know how to test that the proxy is actually used
    it "accepts proxy" do
      io = Down.open("#{$httpbin}/bytes/100", proxy: $httpbin)
      assert_equal 100, io.size

      io = Down.open("#{$httpbin}/bytes/100", proxy: $httpbin.sub("http://", '\0user:password@'))
      assert_equal 100, io.size

      io = Down.open("#{$httpbin}/bytes/100", proxy: URI($httpbin.sub("http://", '\0user:password@')))
      assert_equal 100, io.size
    end

    it "detects and applies basic authentication from URL" do
      io = Down.open("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(io.read)["authenticated"]
    end

    it "saves the response status and headers" do
      io = Down.open("#{$httpbin}/response-headers?Key=Value")
      assert_equal "Value", io.data[:headers]["Key"]
      assert_equal 200,     io.data[:status]
    end

    it "raises an error on 4xx and 5xx response" do
      error = assert_raises(Down::Error) { Down.open("#{$httpbin}/status/404") }
      assert_match "request returned status 404 and body:\n", error.message

      error = assert_raises(Down::Error) { Down.open("#{$httpbin}/status/500") }
      assert_equal "request returned status 500 and body:\n", error.message
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

    it "handles case when there are no chunks" do
      io = chunked_io(chunks: [].each)
      assert_equal "", io.read
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

    it "returns true when there are no chunks" do
      io = chunked_io(chunks: [].each)
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
    assert_nil io.size
    io.read(1)
    assert_equal false, io.eof?
    io.read(1)
    assert_equal false, io.eof?
    io.rewind
    io.read
    assert_equal true, io.eof?
  end
end
