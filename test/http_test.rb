require "test_helper"
require "down/http"
require "http"
require "json"

describe Down::Http do
  before do
    Down::Http.client = nil
  end

  describe "#download" do
    it "downloads content from url" do
      tempfile = Down::Http.download("#{$httpbin}/bytes/100?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/100?seed=0").to_s, tempfile.read
    end

    it "opens the tempfile in binary mode" do
      tempfile = Down::Http.download("#{$httpbin}/bytes/100?seed=0")
      assert tempfile.binmode?
    end

    it "accepts maximum size" do
      assert_raises(Down::TooLarge) do
        Down::Http.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4)
      end

      assert_raises(Down::TooLarge) do
        Down::Http.download("#{$httpbin}/stream-bytes/100", max_size: 50)
      end

      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "infers file extension from url" do
      tempfile = Down::Http.download("#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Http.download("#{$httpbin}/robots.txt?foo=bar")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Http.download("#{$httpbin}/redirect-to?url=#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)
    end

    it "adds #headers and #url" do
      tempfile = Down::Http.download("#{$httpbin}/response-headers?Foo=Bar")
      assert_equal "Bar",                                  tempfile.headers["Foo"]
      assert_equal "#{$httpbin}/response-headers?Foo=Bar", tempfile.url

      tempfile = Down::Http.download("#{$httpbin}/redirect-to?url=#{$httpbin}/response-headers?Foo=Bar")
      assert_equal "Bar",                                  tempfile.headers["Foo"]
      assert_equal "#{$httpbin}/response-headers?Foo=Bar", tempfile.url
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%20filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%2520filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=myfilename.ext%20")
      assert_equal "myfilename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      tempfile = Down::Http.download("#{$httpbin}/robots.txt")
      assert_equal "robots.txt", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/basic-auth/user/pass%20word") do |client|
        client.basic_auth(user: "user", pass: "pass word")
      end
      assert_equal "pass word", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"\"")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}/")
      assert_nil tempfile.original_filename

      tempfile = Down::Http.download("#{$httpbin}")
      assert_nil tempfile.original_filename
    end

    it "adds #content_type extracted from Content-Type" do
      tempfile = Down::Http.download("#{$httpbin}/image/png")
      assert_equal "image/png", tempfile.content_type

      tempfile = Down::Http.download("#{$httpbin}/encoding/utf8")
      assert_equal "text/html; charset=utf-8", tempfile.headers["Content-Type"]
      assert_equal "text/html", tempfile.content_type

      tempfile.headers.delete("Content-Type")
      assert_nil tempfile.content_type

      tempfile.headers["Content-Type"] = nil
      assert_nil tempfile.content_type

      tempfile.headers["Content-Type"] = ""
      assert_nil tempfile.content_type
    end

    it "adds #charset extracted from Content-Type" do
      tempfile = Down::Http.download("#{$httpbin}/get")
      tempfile.headers["Content-Type"] = "text/plain; charset=utf-8"
      assert_equal "utf-8", tempfile.charset

      tempfile.headers.delete("Content-Type")
      assert_nil tempfile.charset

      tempfile.headers["Content-Type"] = nil
      assert_nil tempfile.charset

      tempfile.headers["Content-Type"] = ""
      assert_nil tempfile.charset
    end
  end

  describe "#open" do
    it "returns an IO which streams content" do
      io = Down::Http.open("#{$httpbin}/bytes/1000?seed=0")
      assert_equal HTTP.get("#{$httpbin}/bytes/1000?seed=0").to_s, io.read
    end

    it "sets content length" do
      io = Down::Http.open("#{$httpbin}/bytes/100")
      assert_equal 100, io.size

      io = Down::Http.open("#{$httpbin}/stream-bytes/100")
      assert_nil io.size
    end

    it "follows redirects" do
      tempfile = Down::Http.download("#{$httpbin}/redirect/1")
      assert_equal "http://#{URI($httpbin).host}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down::Http.download("#{$httpbin}/redirect/2")
      assert_equal "http://#{URI($httpbin).host}/get", JSON.parse(tempfile.read)["url"]
      assert_raises(Down::NotFound) { Down::Http.download("#{$httpbin}/redirect/3") }

      tempfile = Down::Http.download("#{$httpbin}/absolute-redirect/1")
      assert_equal "http://#{URI($httpbin).host}/get", JSON.parse(tempfile.read)["url"]
      tempfile = Down::Http.download("#{$httpbin}/relative-redirect/1")
      assert_equal "http://#{URI($httpbin).host}/get", JSON.parse(tempfile.read)["url"]
    end

    it "detects and applies basic authentication from URL" do
      tempfile = Down::Http.download("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "saves response data" do
      io = Down::Http.open("#{$httpbin}/response-headers?Foo=Bar")
      assert_equal 200,                  io.data[:status]
      assert_equal "Bar",                io.data[:headers]["Foo"]
      assert_instance_of HTTP::Response, io.data[:response]
    end

    it "accepts :rewindable option" do
      io = Down::Http.open("#{$httpbin}/bytes/100", rewindable: false)
      assert_raises(IOError) { io.rewind }
    end

    it "forwards additional options to HTTP.rb" do
      io = Down::Http.open("#{$httpbin}/headers", headers: {"Foo" => "Bar"})
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "Bar", request_headers["Foo"]
    end

    it "supports overriding default client" do
      Down::Http.client = Down::Http.client.headers("Foo" => "Bar")
      io = Down::Http.open("#{$httpbin}/headers")
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "Bar", request_headers["Foo"]
    end

    it "supports modifying the client with the chainable interface via a block" do
      io = Down::Http.open("#{$httpbin}/headers") { |client| client.headers("Foo" => "Bar") }
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "Bar", request_headers["Foo"]
    end

    it "uses a default User-Agent" do
      io = Down::Http.open("#{$httpbin}/headers")
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "Down/#{Down::VERSION}", request_headers["User-Agent"]

      io = Down::Http.open("#{$httpbin}/headers", headers: {"User-Agent" => "My-Agent"})
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "My-Agent", request_headers["User-Agent"]

      io = Down::Http.open("#{$httpbin}/headers") { |client| client.headers("User-Agent" => "My-Agent") }
      request_headers = JSON.parse(io.read)["headers"]
      assert_equal "My-Agent", request_headers["User-Agent"]
    end

    it "uses the configured client object for making requests" do
      assert_nil Down::Http.client.instance_variable_get("@connection")
      io = Down::Http.open("#{$httpbin}/bytes/100")
      refute_nil Down::Http.client.instance_variable_get("@connection")
    end

    it "uses a separate client instance for each thread" do
      client1 = Down::Http.client
      client2 = Thread.new { Down::Http.client }.value
      assert_instance_of HTTP::Client, client1
      assert_instance_of HTTP::Client, client2
      refute_equal client1, client2
    end

    it "closes the connection when content has been read" do
      io = Down::Http.open("#{$httpbin}/stream-bytes/1000?chunk_size=10")
      HTTP::Connection.any_instance.expects(:close)
      io.close
    end

    it "closes the connection on IO close" do
      io = Down::Http.open("#{$httpbin}/stream-bytes/1000?chunk_size=10")
      HTTP::Connection.any_instance.expects(:close)
      io.close
    end

    it "doesn't close a persistent connection" do
      Down::Http.client = Down::Http.client.persistent($httpbin)
      io = Down::Http.open("#{$httpbin}/stream-bytes/1000?chunk_size=10")
      HTTP::Connection.any_instance.expects(:close).never
      io.close
    end

    it "raises Down::NotFound on 4xx and 5xx responses" do
      error = assert_raises(Down::NotFound) { Down::Http.open("#{$httpbin}/status/404") }
      assert_equal 404, error.response.code

      error = assert_raises(Down::NotFound) { Down::Http.open("#{$httpbin}/status/500") }
      assert_equal 500, error.response.code
    end

    it "raises Down::NotFound on invalid URL" do
      assert_raises(Down::NotFound) { Down::Http.download("http:\\example.org") }
      assert_raises(Down::NotFound) { Down::Http.download("http:/example.org") }
      assert_raises(Down::NotFound) { Down::Http.download("foo:/example.org") }
      assert_raises(Down::NotFound) { Down::Http.download("#{$httpbin}/get") { |c| c.timeout(read: 0) } }
    end
  end
end
