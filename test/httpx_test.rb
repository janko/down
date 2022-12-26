require "test_helper"
require "down/httpx"
require "httpx"
require "json"

describe Down::Httpx do
  describe "#initialize" do
    it "accepts a hash for overriding options" do
      down = Down::Httpx.new(headers: { "Foo" => "Bar" })
      tempfile = down.download("#{$httpbin}/headers")
      headers = JSON.parse(tempfile.read)["headers"]
      assert_equal "Bar",                   headers["Foo"]
      assert_equal "Down/#{Down::VERSION}", headers["User-Agent"]
    end

    it "accepts a block for overriding options" do
      down = Down::Httpx.new { |client| client.with(headers: { "Foo" => "Bar" }) }
      tempfile = down.download("#{$httpbin}/headers")
      headers = JSON.parse(tempfile.read)["headers"]
      assert_equal "Bar",                   headers["Foo"]
      assert_equal "Down/#{Down::VERSION}", headers["User-Agent"]
    end

    it "accepts request method" do
      [:post, "POST"].each do |method|
        down = Down::Httpx.new(method: method)

        tempfile = down.download("#{$httpbin}/post")
        assert_equal "Down/#{Down::VERSION}", JSON.parse(tempfile.read)["headers"]["User-Agent"]

        io = down.open("#{$httpbin}/post")
        assert_equal "Down/#{Down::VERSION}", JSON.parse(io.read)["headers"]["User-Agent"]
      end
    end
  end

  describe "#download" do
    it "downloads content from url" do
      tempfile = Down::Httpx.download("#{$httpbin}/bytes/100?seed=0")
      assert_equal HTTPX.get("#{$httpbin}/bytes/100?seed=0").to_s, tempfile.read
    end

    it "opens the tempfile in binary mode" do
      tempfile = Down::Httpx.download("#{$httpbin}/bytes/100?seed=0")
      assert tempfile.binmode?
    end

    it "accepts maximum size" do
      error = assert_raises(Down::TooLarge) do
        Down::Httpx.download("#{$httpbin}/bytes/10", max_size: 5)
      end
      assert_match "file is too large (0MB, max is 0MB)", error.message

      assert_raises(Down::TooLarge) do
        Down::Httpx.download("#{$httpbin}/stream-bytes/10", max_size: 5)
      end

      tempfile = Down::Httpx.download("#{$httpbin}/bytes/10", max_size: 10)
      assert File.exist?(tempfile.path)

      tempfile = Down::Httpx.download("#{$httpbin}/stream-bytes/10", max_size: 15)
      assert File.exist?(tempfile.path)
    end

    it "infers file extension from url" do
      tempfile = Down::Httpx.download("#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Httpx.download("#{$httpbin}/robots.txt?foo=bar")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Httpx.download("#{$httpbin}/redirect-to", params: { url: "#{$httpbin}/robots.txt" })
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Httpx.download("#{$httpbin}/robots.txt", extension: "foo")
      assert_equal ".foo", File.extname(tempfile.path)
    end

    it "accepts :content_length_proc" do
      Down::Httpx.download("#{$httpbin}/stream-bytes/100", content_length_proc: -> (length) { @length = length })
      refute instance_variable_defined?(:@length)

      Down::Httpx.download("#{$httpbin}/bytes/100", content_length_proc: -> (length) { @length = length })
      assert_equal 100, @length
    end

    it "accepts :progress_proc" do
      Down::Httpx.download("#{$httpbin}/stream-bytes/100?chunk_size=10", progress_proc: -> (progress) { (@progress ||= []) << progress })
      assert_equal 100, @progress.last
    end

    it "accepts HTTPX options" do
      tempfile = Down::Httpx.download("#{$httpbin}/user-agent", headers: { "User-Agent": "Janko" })
      assert_equal "Janko", JSON.parse(tempfile.read)["user-agent"]
    end

    it "adds #headers and #url" do
      tempfile = Down::Httpx.download("#{$httpbin}/response-headers?Foo=Bar")
      assert_equal "Bar",                                  tempfile.headers["Foo"]
      assert_equal "#{$httpbin}/response-headers?Foo=Bar", tempfile.url

      tempfile = Down::Httpx.download("#{$httpbin}/redirect-to", params: { url: "#{$httpbin}/response-headers?Foo=Bar" })
      assert_equal "Bar",                                  tempfile.headers["Foo"]
      assert_equal "#{$httpbin}/response-headers?Foo=Bar", tempfile.url
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=\"my filename.ext\"" })
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=\"my%20filename.ext\"" })
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=my%20filename.ext" })
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=\"ascii%20filename.ext\"; filename*=UTF-8''utf8%20filename.ext" })
      assert_equal "utf8 filename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      tempfile = Down::Httpx.download("#{$httpbin}/robots.txt")
      assert_equal "robots.txt", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/basic-auth/user/pass%20word") do |client|
        client.basic_auth("user", "pass word")
      end
      assert_equal "pass word", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=" })
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/response-headers", params: { "Content-Disposition": "inline; filename=\"\"" })
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}/")
      assert_nil tempfile.original_filename

      tempfile = Down::Httpx.download("#{$httpbin}")
      assert_nil tempfile.original_filename
    end

    it "adds #content_type extracted from Content-Type" do
      tempfile = Down::Httpx.download("#{$httpbin}/image/png")
      assert_equal "image/png", tempfile.content_type

      tempfile = Down::Httpx.download("#{$httpbin}/encoding/utf8")
      assert_equal "text/html; charset=utf-8", tempfile.headers["Content-Type"]
      assert_equal "text/html", tempfile.content_type
    end

    it "adds #charset extracted from Content-Type" do
      tempfile = Down::Httpx.download("#{$httpbin}/html")
      assert_equal "text/html", tempfile.content_type
      assert_equal "utf-8", tempfile.charset
    end

    it "accepts download destination" do
      tempfile = Tempfile.new("destination")
      result = Down::Httpx.download("#{$httpbin}/bytes/#{20*1024}?seed=0", destination: tempfile.path)
      assert_equal HTTPX.get("#{$httpbin}/bytes/#{20*1024}?seed=0").to_s, File.binread(tempfile.path)
      assert_nil result
    end

    it "accepts request method" do
      [:post, "POST"].each do |method|
        tempfile = Down::Httpx.download("#{$httpbin}/post", method: method)
        assert_equal "Down/#{Down::VERSION}", JSON.parse(tempfile.read)["headers"]["User-Agent"]
      end
    end
  end

  describe "#open" do
    it "returns an IO which streams content" do
      io = Down::Httpx.open("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0")
      assert_equal HTTPX.get("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0").to_s, io.read
    end

    it "follows redirects" do
      io = Down::Httpx.open("#{$httpbin}/redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::Httpx.open("#{$httpbin}/redirect/2")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::Httpx.open("#{$httpbin}/redirect/3") }

      io = Down::Httpx.open("#{$httpbin}/redirect/3", max_redirects: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::Httpx.open("#{$httpbin}/redirect/4", max_redirects: 3) }

      io = Down::Httpx.open("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::Httpx.open("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
    end

    it "returns content in encoding specified by charset" do
      io = Down::Httpx.open("#{$httpbin}/stream/10")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::Httpx.open("#{$httpbin}/get")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::Httpx.open("#{$httpbin}/encoding/utf8")
      assert_equal Encoding::UTF_8, io.read.encoding
    end

    it "sets content length" do
      io = Down::Httpx.open("#{$httpbin}/bytes/100")
      assert_equal 100, io.size

      io = Down::Httpx.open("#{$httpbin}/stream-bytes/100")
      assert_nil io.size
    end

    it "detects and applies basic authentication from URL" do
      tempfile = Down::Httpx.open("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "saves response data" do
      io = Down::Httpx.open("#{$httpbin}/response-headers?Foo=Bar&bar=baz")
      assert_equal 200,                  io.data[:status]
      assert_equal "Bar",                io.data[:headers]["Foo"]
      assert_equal "baz",                io.data[:headers]["Bar"]
      assert_instance_of HTTPX::StreamResponse, io.data[:response]
    end

    it "accepts :rewindable option" do
      io = Down::Httpx.open("#{$httpbin}/bytes/100", rewindable: false)
      assert_raises(IOError) { io.rewind }
    end

    it "uses a default User-Agent" do
      io = Down::Httpx.open("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(io.read)["user-agent"]
    end

    it "forwards additional options to HTTP.rb" do
      io = Down::Httpx.open("#{$httpbin}/user-agent", headers: {"User-Agent" => "Janko"})
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end

    it "supports modifying the client with the chainable interface via a block" do
      io = Down::Httpx.open("#{$httpbin}/user-agent") { |client| client.with(headers: { "User-Agent" => "Janko" }) }
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end

    it "closes the response body when content has been read" do
      io = Down::Httpx.open("#{$httpbin}/stream-bytes/1000?chunk_size=10")
      HTTPX::Response::Body.any_instance.expects(:close)
      io.close
    end

    it "closes the body on IO close" do
      io = Down::Httpx.open("#{$httpbin}/stream-bytes/1000?chunk_size=10")
      HTTPX::Response::Body.any_instance.expects(:close)
      io.close
    end

    it "accepts request method" do
      [:post, "POST"].each do |method|
        io = Down::Httpx.open("#{$httpbin}/post", method: method)
        assert_equal "Down/#{Down::VERSION}", JSON.parse(io.read)["headers"]["User-Agent"]
      end
    end

    it "raises on HTTP error responses" do
      error = assert_raises(Down::NotFound) { Down::Httpx.open("#{$httpbin}/status/404") }
      assert_equal "404", error.message
      assert_instance_of HTTPX::StreamResponse, error.response

      error = assert_raises(Down::ClientError) { Down::Httpx.open("#{$httpbin}/status/403") }
      assert_equal "403", error.message
      assert_instance_of HTTPX::StreamResponse, error.response

      error = assert_raises(Down::ServerError) { Down::Httpx.open("#{$httpbin}/status/500") }
      assert_equal "500", error.message
      assert_instance_of HTTPX::StreamResponse, error.response

      error = assert_raises(Down::ResponseError) { Down::Httpx.open("#{$httpbin}/status/100") }
      assert_equal "100", error.message
      assert_instance_of HTTPX::StreamResponse, error.response
    end

    it "re-raises invalid URL errors" do
      assert_raises(Down::InvalidUrl) { Down::Httpx.open("foo://example.org") }
      assert_raises(Down::InvalidUrl) { Down::Httpx.open("http://example.org\\foo") }
    end

    it "re-raises connection errors" do
      assert_raises(Down::ConnectionError) { Down::Httpx.open("http://localhost:99999") }
    end

    it "re-raises timeout errors" do
      assert_raises(Down::TimeoutError) { Down::Httpx.open("#{$httpbin}/delay/0.5"){ |c| c.with(timeout: { read_timeout: 0 })}.read }
    end

    it "re-raises SSL errors" do
      assert_raises(Down::SSLError) { Down::Httpx.open("https://expired.badssl.com/") }
    end

    it "re-raises other exceptions" do
      assert_raises(HTTPX::Error) { Down::Httpx.open("http://32r3ida") }
    end
  end
end
