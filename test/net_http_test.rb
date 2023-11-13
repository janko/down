require "test_helper"

require "down/net_http"
require "http"

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

      tempfile = Down::NetHttp.download("#{$httpbin}/robots.txt", extension: "foo")
      assert_equal ".foo", File.extname(tempfile.path)
    end

    it "accepts an URI object" do
      tempfile = Down::NetHttp.download(URI("#{$httpbin}/bytes/100"))
      assert_equal 100, tempfile.size
    end

    it "uses a default User-Agent" do
      tempfile = Down::NetHttp.download("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(tempfile.read)["user-agent"]
    end

    it "accepts max size" do
      error = assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/bytes/10", max_size: 5)
      end
      assert_match "file is too large (0MB, max is 0MB)", error.message

      assert_raises(Down::TooLarge) do
        Down::NetHttp.download("#{$httpbin}/stream-bytes/10", max_size: 5)
      end

      tempfile = Down::NetHttp.download("#{$httpbin}/bytes/10", max_size: 10)
      assert File.exist?(tempfile.path)

      tempfile = Down::NetHttp.download("#{$httpbin}/stream-bytes/10", max_size: 15)
      assert File.exist?(tempfile.path)
    end

    it "accepts content length proc" do
      Down::NetHttp.download "#{$httpbin}/bytes/100",
        content_length_proc: ->(n) { @content_length = n }

      assert_equal 100, @content_length
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
      assert_raises(Down::TooManyRedirects) { Down::NetHttp.download("#{$httpbin}/redirect/3") }

      tempfile = Down::NetHttp.download("#{$httpbin}/redirect/3", max_redirects: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::NetHttp.download("#{$httpbin}/redirect/4", max_redirects: 3) }

      tempfile = Down::NetHttp.download("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down::NetHttp.download("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(tempfile.read)["url"]

      # We also want to test that cookies are being forwarded on redirects, but
      # httpbin doesn't have an endpoint which can both redirect and return a
      # "Set-Cookie" header.
    end

    it "removes Authorization header on  redirects" do
      tempfile = Down::NetHttp.download("#{$httpbin}/redirect/1", headers: {"Authorization" => "Basic dXNlcjpwYXNzd29yZA=="})
      assert_nil JSON.parse(tempfile.read)["headers"]["Authorization"]
    end

    it "removes Baisic Auth credentials header on  redirects" do
      tempfile = Down::NetHttp.download("#{$httpbin.sub("http://", '\0user:password@')}/redirect/1", )
      assert_nil JSON.parse(tempfile.read)["headers"]["Authorization"]
    end

    it "preserves Authorization header on redirect, when asked" do
      tempfile = Down::NetHttp.download("#{$httpbin.sub("http://", '\0user:password@')}/redirect/1", auth_on_redirect:true )
      assert_equal "Basic dXNlcjpwYXNzd29yZA==", JSON.parse(tempfile.read)["headers"]["Authorization"]
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

    it "accepts request headers" do
      tempfile = Down::NetHttp.download("#{$httpbin}/headers", headers: { "Key" => "Value" })
      assert_equal "Value", JSON.parse(tempfile.read)["headers"]["Key"]
    end

    it "forwards other options to open-uri" do
      tempfile = Down::NetHttp.download("#{$httpbin}/basic-auth/user/password", http_basic_authentication: ["user", "password"])
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "applies default options" do
      net_http = Down::NetHttp.new(headers: { "User-Agent" => "Janko" })
      tempfile = net_http.download("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(tempfile.read)["user-agent"]
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%20filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%2520filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=my%2520filename.ext; size=3718678")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::NetHttp.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"ascii%20filename.ext\"%3B%20filename*=UTF-8''utf8%2520filename.ext")
      assert_equal "utf8 filename.ext", tempfile.original_filename
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

      tempfile = Down::NetHttp.download("#{$httpbin}/encoding/utf8")
      assert_equal "text/html; charset=utf-8", tempfile.meta["content-type"]
      assert_equal "text/html", tempfile.content_type

      tempfile.meta.delete("content-type")
      assert_nil tempfile.content_type

      tempfile.meta["content-type"] = nil
      assert_nil tempfile.content_type

      tempfile.meta["content-type"] = ""
      assert_nil tempfile.content_type
    end

    it "accepts download destination" do
      tempfile = Tempfile.new("destination")
      result = Down::NetHttp.download("#{$httpbin}/bytes/#{20*1024}?seed=0", destination: tempfile.path)
      assert_equal HTTP.get("#{$httpbin}/bytes/#{20*1024}?seed=0").to_s, File.binread(tempfile.path)
      assert_nil result
    end

    it "raises on HTTP error responses" do
      error = assert_raises(Down::NotFound) { Down::NetHttp.download("#{$httpbin}/status/404") }
      assert_equal "404 Not Found", error.message
      assert_kind_of Net::HTTPResponse, error.response

      error = assert_raises(Down::ClientError) { Down::NetHttp.download("#{$httpbin}/status/403") }
      assert_equal "403 Forbidden", error.message
      assert_kind_of Net::HTTPResponse, error.response

      error = assert_raises(Down::ServerError) { Down::NetHttp.download("#{$httpbin}/status/500") }
      assert_equal "500 Internal Server Error", error.message
      assert_kind_of Net::HTTPResponse, error.response

      error = assert_raises(Down::ServerError) { Down::NetHttp.download("#{$httpbin}/status/599") }
      assert_equal "599 Unknown", error.message
      assert_kind_of Net::HTTPResponse, error.response

      error = assert_raises(Down::ResponseError) { Down::NetHttp.download("#{$httpbin}/status/999") }
      assert_equal "999 Unknown", error.message
      assert_kind_of Net::HTTPResponse, error.response
    end

    it "accepts non-escaped URLs" do
      tempfile = Down::NetHttp.download("#{$httpbin}/etag/foo bar")
      assert_equal "foo bar", tempfile.meta["etag"]
    end

    it "only normalizes URLs when URI says the URL is invalid" do
      url = "#{$httpbin}/etag/2ELk8hUpTC2wqJ%2BZ%25GfTFA.jpg"
      tempfile = Down::NetHttp.download(url)
      assert_equal url, tempfile.base_uri.to_s
    end

    it "accepts :uri_normalizer" do
      assert_raises(Down::InvalidUrl) do
        Down::NetHttp.download("#{$httpbin}/etag/foo bar", uri_normalizer: -> (uri) { uri })
      end
    end

    it "raises on invalid URLs" do
      assert_raises(Down::InvalidUrl) { Down::NetHttp.download("foo://example.org") }
      assert_raises(Down::InvalidUrl) { Down::NetHttp.download("| ls") }
    end

    it "raises on invalid redirect url" do
      assert_raises(Down::ResponseError) { Down::NetHttp.download("#{$httpbin}/redirect-to?url=#{CGI.escape("ftp://localhost/file.txt")}") }
    end

    it "raises on connection errors" do
      assert_raises(Down::ConnectionError) { Down::NetHttp.download("http://localhost:9999") }
    end

    it "raises on timeout errors" do
      assert_raises(Down::TimeoutError) { Down::NetHttp.download("#{$httpbin}/delay/0.5", read_timeout: 0, open_timeout: 0) }
    end

    it "doesn't trip up on unknown response status" do
      assert_raises(Down::ClientError) { Down::NetHttp.download("#{$httpbin}/status/444") }
    end

    deprecated "accepts top-level request headers" do
      tempfile = Down::NetHttp.download("#{$httpbin}/headers", { "Key" => "Value" })
      assert_equal "Value", JSON.parse(tempfile.read)["headers"]["Key"]

      tempfile = Down::NetHttp.download("#{$httpbin}/headers", "Key" => "Value")
      assert_equal "Value", JSON.parse(tempfile.read)["headers"]["Key"]

      net_http = Down::NetHttp.new({ "User-Agent" => "Janko" })
      tempfile = net_http.download("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(tempfile.read)["user-agent"]

      net_http = Down::NetHttp.new("User-Agent" => "Janko")
      tempfile = net_http.download("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(tempfile.read)["user-agent"]
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

    it "follows redirects" do
      io = Down::NetHttp.open("#{$httpbin}/redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::NetHttp.open("#{$httpbin}/redirect/2")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::NetHttp.open("#{$httpbin}/redirect/3") }

      io = Down::NetHttp.open("#{$httpbin}/redirect/3", max_redirects: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::NetHttp.open("#{$httpbin}/redirect/4", max_redirects: 3) }

      io = Down::NetHttp.open("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::NetHttp.open("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
    end

    it "removes Authorization header on  redirects" do
      io = Down::NetHttp.open("#{$httpbin}/redirect/1", headers: {"Authorization" => "Basic dXNlcjpwYXNzd29yZA=="})
      assert_nil JSON.parse(io.read)["headers"]["Authorization"]
    end

    it "removes Baisic Auth credentials header on  redirects" do
      io = Down::NetHttp.open("#{$httpbin.sub("http://", '\0user:password@')}/redirect/1", )
      assert_nil JSON.parse(io.read)["headers"]["Authorization"]
    end

    it "preserves Authorization header on redirect, when asked" do
      io = Down::NetHttp.open("#{$httpbin.sub("http://", '\0user:password@')}/redirect/1", auth_on_redirect:true )
      assert_equal "Basic dXNlcjpwYXNzd29yZA==", JSON.parse(io.read)["headers"]["Authorization"]
    end

    it "returns content in encoding specified by charset" do
      io = Down::NetHttp.open("#{$httpbin}/stream/10")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::NetHttp.open("#{$httpbin}/get")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::NetHttp.open("#{$httpbin}/encoding/utf8")
      assert_equal Encoding::UTF_8, io.read.encoding
    end

    it "uses a default User-Agent" do
      io = Down::NetHttp.open("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(io.read)["user-agent"]
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
      io = Down::NetHttp.open("#{$httpbin}/headers", headers: { "Key" => "Value" })
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

    it "accepts :http_basic_authentication_option" do
      io = Down::NetHttp.open("#{$httpbin}/basic-auth/user/password", http_basic_authentication: ["user", "password"])
      assert_equal true, JSON.parse(io.read)["authenticated"]
    end

    it "detects and applies basic authentication from URL" do
      io = Down::NetHttp.open("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(io.read)["authenticated"]
    end

    it "applies default options" do
      net_http = Down::NetHttp.new(headers: { "User-Agent" => "Janko" })
      io = net_http.open("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end

    it "saves response data" do
      io = Down::NetHttp.open("#{$httpbin}/response-headers?Key=Value&bar=baz")
      assert_equal "Value",             io.data[:headers]["Key"]
      assert_equal "baz",               io.data[:headers]["Bar"]
      assert_equal 200,                 io.data[:status]
      assert_kind_of Net::HTTPResponse, io.data[:response]
    end

    # The response URI is only available if a URI was used to create the request.
    # https://ruby-doc.org/stdlib-2.7.0/libdoc/net/http/rdoc/Net/HTTPResponse.html#uri
    it "constructs http response with #uri attribute set" do
      io = Down::NetHttp.open("#{$httpbin}/get")
      assert_equal URI("#{$httpbin}/get"), io.data[:response].uri

      io = Down::NetHttp.open("#{$httpbin}/redirect/1")
      assert_equal URI("#{$httpbin}/get"), io.data[:response].uri # redirected uri
    end

    it "raises on HTTP error responses" do
      error = assert_raises(Down::ClientError) { Down::NetHttp.open("#{$httpbin}/status/404") }
      assert_equal "404 Not Found", error.message
      assert_kind_of Net::HTTPResponse, error.response

      error = assert_raises(Down::ServerError) { Down::NetHttp.open("#{$httpbin}/status/500") }
      assert_equal "500 Internal Server Error", error.message
      assert_kind_of Net::HTTPResponse, error.response
    end

    it "accepts non-escaped URLs" do
      io = Down::NetHttp.open("#{$httpbin}/etag/foo bar")
      assert_equal "foo bar", io.data[:headers]["Etag"]
    end

    it "accepts :uri_normalizer" do
      assert_raises(Down::InvalidUrl) do
        Down::NetHttp.open("#{$httpbin}/etag/foo bar", uri_normalizer: -> (uri) { uri })
      end
    end

    it "raises on invalid URLs" do
      assert_raises(Down::InvalidUrl) { Down::NetHttp.open("foo://example.org") }
    end

    it "raises on invalid redirect url" do
      assert_raises(Down::ResponseError) { Down::NetHttp.open("#{$httpbin}/redirect-to?url=#{CGI.escape("ftp://localhost/file.txt")}") }
    end

    it "raises on redirect not modfied" do
      assert_raises(Down::NotModified) { Down::NetHttp.open("#{$httpbin}/status/304") }
    end

    it "raises on connection errors" do
      assert_raises(Down::ConnectionError) { Down::NetHttp.open("http://localhost:9999") }
    end

    it "raises on timeout errors" do
      assert_raises(Down::TimeoutError) { Down::NetHttp.open("#{$httpbin}/delay/0.5", read_timeout: 0).read }
    end

    it "re-raises SSL errors" do
      if defined?(Net::HTTP::VERSION) && Net::HTTP::VERSION.start_with?("0.2")
        Socket.expects(:tcp).raises(OpenSSL::SSL::SSLError)
      else
        TCPSocket.expects(:open).raises(OpenSSL::SSL::SSLError)
      end

      assert_raises(Down::SSLError) { Down::NetHttp.open($httpbin) }
    end

    it "re-raises other exceptions" do
      if defined?(Net::HTTP::VERSION) && Net::HTTP::VERSION.start_with?("0.2")
        Socket.expects(:tcp).raises(ArgumentError)
      else
        TCPSocket.expects(:open).raises(ArgumentError)
      end

      assert_raises(ArgumentError) { Down::NetHttp.open($httpbin) }
    end

    deprecated "accepts top-level request headers" do
      io = Down::NetHttp.open("#{$httpbin}/headers", { "Key" => "Value" })
      assert_equal "Value", JSON.parse(io.read)["headers"]["Key"]

      io = Down::NetHttp.open("#{$httpbin}/headers", "Key" => "Value")
      assert_equal "Value", JSON.parse(io.read)["headers"]["Key"]

      net_http = Down::NetHttp.new({ "User-Agent" => "Janko" })
      io = net_http.open("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]

      net_http = Down::NetHttp.new("User-Agent" => "Janko")
      io = net_http.open("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end
  end
end
