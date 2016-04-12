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

    it "accepts progress" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      size = nil
      Down.download("http://example.com/image.jpg", progress: proc { |s| size = s })
      assert_equal 5, size
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
      stub_request(:get, "http://example.com/image%20space.jpg").to_return(body: "a" * 20 * 1024, headers: {'Content-Type' => 'image/jpeg'})
      tempfile = Down.download("http://example.com/image%20space.jpg")
      assert_equal "image space.jpg", tempfile.original_filename
    end

    it "makes original fileame return nil when path is missing" do
      stub_request(:get, "http://example.com").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com")
      assert_equal nil, tempfile.original_filename

      stub_request(:get, "http://example.com/").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/")
      assert_equal nil, tempfile.original_filename
    end

    it "raises NotFound on HTTP errors" do
      stub_request(:get, "http://example.com").to_return(status: 404)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }

      stub_request(:get, "http://example.com").to_return(status: 500)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }
    end

    it "doesn't allow redirects by default" do
      stub_request(:get, "http://example.com").to_return(status: 301, headers: {'Location' => 'http://example2.com'})
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

    it "forwards options to open-uri" do
      stub_request(:get, "http://example.com").to_return(status: 301, headers: {'Location' => 'http://example2.com'})
      stub_request(:get, "http://example2.com").to_return(body: "redirected")
      tempfile = Down.download("http://example.com", redirect: true)
      assert_equal "redirected", tempfile.read
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
