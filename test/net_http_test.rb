require "test_helper"

require "down/net_http"

require "stringio"
require "json"
require "base64"

describe Down do
  describe "#download" do
    it "downloads content from url" do
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{20*1024}?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/#{20*1024}?seed=0").to_s, tempfile.read

      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{1024}?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/#{1024}?seed=0").to_s, tempfile.read
    end

    it "returns a Tempfile" do
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{20*1024}")
      assert_instance_of Tempfile, tempfile

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{1024}")
      assert_instance_of Tempfile, tempfile
    end

    it "saves Tempfile to disk" do
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{20*1024}")
      assert File.exist?(tempfile.path)

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{1024}")
      assert File.exist?(tempfile.path)
    end

    it "opens the Tempfile in binary mode" do
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{20*1024}")
      assert tempfile.binmode?

      # open-uri returns a StringIO on files with 10KB or less
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/#{1024}")
      assert tempfile.binmode?
    end

    it "gives the Tempfile a file extension" do
      tempfile = Down::NetHttp.download("#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::NetHttp.download("#{$httpbin}/robots.txt?foo=bar")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::NetHttp.download("#{$httpbin}/redirect-to?url=#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)
    end

    it "accepts an URI object" do
      tempfile = Down::NetHttp.download(URI("#{$httpbin}/bytes/100"))
      assert_equal 100, tempfile.size
    end

    it "uses a default User-Agent" do
      tempfile = Down::NetHttp.download("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(tempfile.read)["user-agent"]

      tempfile = Down::NetHttp.download("#{$httpbin}/user-agent", {"User-Agent" => "Custom/Agent"})
      assert_equal "Custom/Agent", JSON.parse(tempfile.read)["user-agent"]
    end

    it "accepts max size" do
      assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4)
      end
      assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4, content_length_proc: ->(n){})
      end

      assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/stream-bytes/100", max_size: 50)
      end
      assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/stream-bytes/100", max_size: 50, progress_proc: ->(n){})
      end

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "accepts content length proc" do
      Down::NetHttp.download "#{$httpbin}/response-headers?Content-Length=10",
        content_length_proc: ->(n) { @content_length = n }

      assert_equal 10, @content_length
    end

    it "accepts progress proc" do
      Down::NetHttp.download "#{$httpbin}/stream-bytes/100?chunk_size=10",
        progress_proc: ->(n) { (@progress ||= []) << n }

      assert_equal [10, 20, 30, 40, 50, 60, 70, 80, 90, 100], @progress
    end

    it "detects and applies basic authentication from URL" do
      tempfile = Down::NetHttp.download("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "follows redirects" do
      tempfile = Down::NetHttp.download("#{$httpbin}/redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down::NetHttp.download("#{$httpbin}/redirect/2")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      error = assert_raises(Down::Error) { Down::NetHttp.download("#{$httpbin}/redirect/3") }
      assert_equal "too many redirects", error.message

      tempfile = Down::NetHttp.download("#{$httpbin}/redirect/3", max_redirects: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      error = assert_raises(Down::Error) { Down::NetHttp.download("#{$httpbin}/redirect/4", max_redirects: 3) }
      assert_equal "too many redirects", error.message

      tempfile = Down::NetHttp.download("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down::NetHttp.download("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]

      # We also want to test that cookies are being forwarded on redirects, but
      # httpbin doesn't have an endpoint which can both redirect and return a
      # "Set-Cookie" header.
    end

    # I don't know how to test that the proxy is actually used
    it "accepts proxy" do
      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/100", proxy: $httpbin)
      assert_equal 100, tempfile.size

      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/100", proxy: $httpbin.sub("http://", '\0user:password@'))
      assert_equal 100, tempfile.size

      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/100", proxy: URI($httpbin.sub("http://", '\0user:password@')))
      assert_equal 100, tempfile.size
    end

    it "forwards other options to open-uri" do
      tempfile = Down::NetHttp.download("#{$httpbin}/basic-auth/user/password", http_basic_authentication: ["user", "password"])
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]

      tempfile = Down::NetHttp.download("#{$httpbin}/basic-auth/user/password", {"Authorization" => "Basic #{Base64.encode64("user:password")}"})
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%20filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%2520filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=myfilename.ext ")
      assert_equal "myfilename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      tempfile = Down::NetHttp.download("#{$httpbin}/robots.txt")
      assert_equal "robots.txt", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/basic-auth/user/pass%20word", http_basic_authentication: ["user", "pass word"])
      assert_equal "pass word", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"\"")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/")
      assert_nil tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}")
      assert_nil tempfile.original_filename
    end

    it "adds #content_type extracted from Content-Type" do
      tempfile = Down::NetHttp.download("#{$httpbin}/image/png")
      assert_equal "image/png", tempfile.content_type

      tempfile.meta.delete("content-type")
      assert_nil tempfile.content_type

      tempfile.meta["content-type"] = nil
      assert_nil tempfile.content_type

      tempfile.meta["content-type"] = ""
      assert_nil tempfile.content_type
    end

    it "raises NotFound on HTTP error responses" do
      assert_raises(Down::NotFound) { Down::NetHttp.download("#{$httpbin}/status/400") }
      assert_raises(Down::NotFound) { Down::NetHttp.download("#{$httpbin}/status/500") }
    end

    it "raises NotFound on invalid URL" do
      assert_raises(Down::NotFound) { Down::NetHttp.download("http:\\example.org") }
      assert_raises(Down::NotFound) { Down::NetHttp.download("http:/example.org") }
      assert_raises(Down::NotFound) { Down::NetHttp.download("foo:/example.org") }
      assert_raises(Down::NotFound) { Down::NetHttp.download("#{$httpbin}/get", read_timeout: 0) }
    end

    it "doesn't allow shell execution" do
      assert_raises(Down::Error) { Down::NetHttp.download("| ls") }
    end
  end

  describe "#open" do
    it "streams response body in chunks" do
      io = Down::NetHttp.open("#{$httpbin}/stream/10")
      assert_equal 10, io.each_chunk.count
    end

    it "accepts an URI object" do
      io = Down::NetHttp.open(URI("#{$httpbin}/stream/10"))
      assert_equal 10, io.each_chunk.count
    end

    it "downloads on demand" do
      start = Time.now
      io = Down::NetHttp.open("#{$httpbin}/drip?duration=0.5&delay=0")
      io.close
      assert_operator Time.now - start, :<, 0.5
    end

    it "doesn't have to be rewindable" do
      io = Down::NetHttp.open("#{$httpbin}/stream/10", rewindable: false)
      io.read
      assert_raises(IOError) { io.rewind }
    end

    it "extracts size from Content-Length" do
      io = Down::NetHttp.open(URI("#{$httpbin}/bytes/100"))
      assert_equal 100, io.size

      io = Down::NetHttp.open(URI("#{$httpbin}/stream-bytes/100"))
      assert_nil io.size
    end

    it "closes the connection on #close" do
      io = Down::NetHttp.open("#{$httpbin}/bytes/100")
      Net::HTTP.any_instance.expects(:do_finish)
      io.close
    end

    it "accepts request headers" do
      io = Down::NetHttp.open("#{$httpbin}/headers", {"Key" => "Value"})
      assert_equal "Value", JSON.parse(io.read)["headers"]["Key"]
    end

    # I don't know how to test that the proxy is actually used
    it "accepts proxy" do
      io = Down::NetHttp.open("#{$httpbin}/bytes/100", proxy: $httpbin)
      assert_equal 100, io.size

      io = Down::NetHttp.open("#{$httpbin}/bytes/100", proxy: $httpbin.sub("http://", '\0user:password@'))
      assert_equal 100, io.size

      io = Down::NetHttp.open("#{$httpbin}/bytes/100", proxy: URI($httpbin.sub("http://", '\0user:password@')))
      assert_equal 100, io.size
    end

    it "detects and applies basic authentication from URL" do
      io = Down::NetHttp.open("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(io.read)["authenticated"]
    end

    it "saves response data" do
      io = Down::NetHttp.open("#{$httpbin}/response-headers?Key=Value")
      assert_equal "Value",             io.data[:headers]["Key"]
      assert_equal 200,                 io.data[:status]
      assert_kind_of Net::HTTPResponse, io.data[:response]
    end

    it "raises an error on 4xx and 5xx response" do
      error = assert_raises(Down::Error) { Down::NetHttp.open("#{$httpbin}/status/404") }
      assert_match "request returned status 404 and body:\n", error.message

      error = assert_raises(Down::Error) { Down::NetHttp.open("#{$httpbin}/status/500") }
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
