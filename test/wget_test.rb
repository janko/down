require "test_helper"
require "down/wget"
require "http"
require "json"
require "uri"

describe Down::Wget do
  describe "#download" do
    it "downloads ASCII content from url" do
      tempfile = Down::Wget.open("#{$httpbin}/range/1000?chunk_size=10&seed=0")
      assert_equal HTTP.get("#{$httpbin}/range/1000?chunk_size=10&seed=0").to_s, tempfile.read
    end

    it "downloads binary content from url" do
      tempfile = Down::Wget.open("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0")
      assert_equal HTTP.get("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0").to_s, tempfile.read
    end

    it "opens the tempfile in binary mode" do
      tempfile = Down::Wget.download("#{$httpbin}/bytes/100")
      assert tempfile.binmode?
    end

    it "accepts maximum size" do
      assert_raises(Down::TooLarge) do
        Down::Wget.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 4)
      end

      assert_raises(Down::TooLarge) do
        Down::Wget.download("#{$httpbin}/stream-bytes/100", max_size: 50)
      end

      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Length=5", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "accepts :content_length_proc" do
      tempfile = Down::Wget.download("#{$httpbin}/stream-bytes/100", content_length_proc: -> (length) { @length = length })
      refute instance_variable_defined?(:@length)

      tempfile = Down::Wget.download("#{$httpbin}/bytes/100", content_length_proc: -> (length) { @length = length })
      assert_equal 100, @length
    end

    it "accepts :progress_proc" do
      tempfile = Down::Wget.download("#{$httpbin}/stream-bytes/100?chunk_size=10", progress_proc: -> (progress) { (@progress ||= []) << progress })
      assert_equal 100, @progress.last
    end

    it "infers file extension from url" do
      tempfile = Down::Wget.download("#{$httpbin}/robots.txt")
      assert_equal ".txt", File.extname(tempfile.path)

      tempfile = Down::Wget.download("#{$httpbin}/robots.txt?foo=bar")
      assert_equal ".txt", File.extname(tempfile.path)
    end

    it "adds #headers and #url" do
      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Foo=Bar")
      assert_equal "Bar",                                  tempfile.headers["Foo"]
      assert_equal "#{$httpbin}/response-headers?Foo=Bar", tempfile.url
    end

    it "adds #original_filename extracted from Content-Disposition" do
      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%20filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"my%2520filename.ext\"")
      assert_equal "my filename.ext", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=myfilename.ext%20")
      assert_equal "myfilename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      tempfile = Down::Wget.download("#{$httpbin}/robots.txt")
      assert_equal "robots.txt", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin.sub("http://", '\0user:pass%20word@')}/basic-auth/user/pass%20word")
      assert_equal "pass word", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}/response-headers?Content-Disposition=inline;%20filename=\"\"")
      assert_equal "response-headers", tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}/")
      assert_nil tempfile.original_filename

      tempfile = Down::Wget.download("#{$httpbin}")
      assert_nil tempfile.original_filename
    end

    it "adds #content_type extracted from Content-Type" do
      tempfile = Down::Wget.download("#{$httpbin}/image/png")
      assert_equal "image/png", tempfile.content_type

      tempfile = Down::Wget.download("#{$httpbin}/encoding/utf8")
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
      tempfile = Down::Wget.download("#{$httpbin}/get")
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
    it "retrieves ASCII body" do
      io = Down::Wget.open("#{$httpbin}/range/1000?chunk_size=10&seed=0")
      assert_equal HTTP.get("#{$httpbin}/range/1000?chunk_size=10&seed=0").to_s, io.read
    end

    it "retrieves binary body" do
      io = Down::Wget.open("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0")
      assert_equal HTTP.get("#{$httpbin}/stream-bytes/1000?chunk_size=10&seed=0").to_s, io.read
    end

    it "follows redirects" do
      io = Down::Wget.open("#{$httpbin}/redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::Wget.open("#{$httpbin}/redirect/2")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::Wget.open("#{$httpbin}/redirect/3") }

      io = Down::Wget.open("#{$httpbin}/redirect/3", max_redirect: 3)
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      assert_raises(Down::TooManyRedirects) { Down::Wget.open("#{$httpbin}/redirect/4", max_redirect: 3) }

      io = Down::Wget.open("#{$httpbin}/absolute-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
      io = Down::Wget.open("#{$httpbin}/relative-redirect/1")
      assert_equal "#{$httpbin}/get", JSON.parse(io.read)["url"]
    end

    it "uses default user agent" do
      io = Down::Wget.open("#{$httpbin}/user-agent")
      assert_equal "Down/#{Down::VERSION}", JSON.parse(io.read)["user-agent"]
    end

    it "automatically applies basic authentication" do
      tempfile = Down::Wget.open("#{$httpbin.sub("http://", '\0user:password@')}/basic-auth/user/password")
      assert_equal true, JSON.parse(tempfile.read)["authenticated"]
    end

    it "returns content in encoding specified by charset" do
      io = Down::Wget.open("#{$httpbin}/stream/10")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::Wget.open("#{$httpbin}/get")
      assert_equal Encoding::BINARY, io.read.encoding

      io = Down::Wget.open("#{$httpbin}/encoding/utf8")
      assert_equal Encoding::UTF_8, io.read.encoding
    end

    it "saves #size" do
      io = Down::Wget.open("#{$httpbin}/bytes/100")
      assert_equal 100, io.size

      io = Down::Wget.open("#{$httpbin}/stream-bytes/100")
      assert_nil io.size
    end

    it "saves response data" do
      io = Down::Wget.open("#{$httpbin}/response-headers?Header=Value")
      assert_equal 200,     io.data[:status]
      assert_equal "Value", io.data[:headers]["Header"]
    end

    it "closes the command" do
      io = Down::Wget.open("#{$httpbin}/bytes/100")
      io.close

      io = Down::Wget.open("#{$httpbin}/bytes/100")
      io.read
      io.close
    end

    it "accepts command-line arguments" do
      io = Down::Wget.open("#{$httpbin}/user-agent", user_agent: "Janko")
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end

    it "can set default arguments" do
      wget = Down::Wget.new(user_agent: "Janko")
      io = wget.open("#{$httpbin}/user-agent")
      assert_equal "Janko", JSON.parse(io.read)["user-agent"]
    end

    it "raises on timeout errors" do
      assert_raises(Down::TimeoutError) do
        Down::Wget.open("#{$httpbin}/delay/0.5", read_timeout: 0.0001, tries: 1)
      end
    end

    it "raises on invalid URL" do
      assert_raises(Down::Error) { Down::Wget.open("foo://bar.com") }
    end

    it "raises on parser errors" do
      assert_raises(Down::Error) { Down::Wget.open("#{$httpbin}/get", foo: "bar") }
    end

    it "raises on connection errors" do
      assert_raises(Down::ConnectionError) { Down::Wget.open("localhost:9999") }
    end

    it "raises on authentication failures" do
      assert_raises(Down::ResponseError) { Down::Wget.open("#{$httpbin}/basic-auth/user/pass") }
    end

    it "raises on error responses" do
      assert_raises(Down::ResponseError) { Down::Wget.open("#{$httpbin}/status/404") }
      assert_raises(Down::ResponseError) { Down::Wget.open("#{$httpbin}/status/500") }
    end
  end
end
