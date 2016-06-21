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

  describe "#open" do
    before do
      mocked_http = Class.new(Net::HTTP) do
        def request(*)
          super do |response|
            response.instance_eval do
              def read_body
                yield "ab"
                yield "c"
              end
            end
            yield response if block_given?
          end
        end
      end

      @original_net_http = Net.send(:remove_const, :HTTP)
      Net.send(:const_set, :HTTP, mocked_http)
    end

    after do
      Net.send(:remove_const, :HTTP)
      Net.send(:const_set, :HTTP, @original_net_http)
    end

    it "gets the size from Content-Length" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 3, io.size
      assert_equal 0, io.tempfile.size
    end

    it "can read the whole content" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal false, io.eof?
      assert_equal "abc", io.read
      assert_equal true, io.eof?
    end

    it "can read parts of content" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal "a", io.read(1)
      assert_equal false, io.eof?
      assert_equal "bc", io.read
      assert_equal true, io.eof?
      assert_equal "", io.read
    end

    it "downloads the next chunk only when needed" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 0, io.tempfile.size
      io.read(1)
      assert_equal 2, io.tempfile.size
      io.read(1)
      assert_equal 2, io.tempfile.size
      io.read(1)
      assert_equal 3, io.tempfile.size
    end

    it "can rewind the IO" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal "ab", io.read(2)
      io.rewind
      assert_equal "ab", io.read(2)
      assert_equal 2, io.tempfile.size
    end

    it "can yield chunks" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal ["ab", "c"], io.each_chunk.to_a
    end

    it "works as expected without Content-Length" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      assert_equal nil, io.size
      assert_equal false, io.eof?
      assert_equal "abc", io.read
      assert_equal true, io.eof?
    end

    it "closes the connection on close" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      Net::HTTP.any_instance.expects(:do_finish)
      io.close
    end

    it "deletes the underlying tempfile on close" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      io.close
      assert_equal nil, io.tempfile.path
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
