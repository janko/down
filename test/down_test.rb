require "test_helper"
require "stringio"
require "timeout"

class DownloadTest < Minitest::Test
  def test_downloads_url_to_disk
    stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024)
    tempfile = Down.download("http://example.com/image.jpg")

    assert_instance_of Tempfile, tempfile
    assert File.exist?(tempfile.path)
  end

  def test_converts_small_stringios_to_tempfiles
    stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5)
    tempfile = Down.download("http://example.com/small.jpg")

    assert_instance_of Tempfile, tempfile
    assert File.exist?(tempfile.path)
    assert_equal "aaaaa", tempfile.read
  end

  def test_encodes_the_url
    stub_request(:get, "http://example.com/some%20image.jpg").to_return(body: "a" * 5)
    tempfile = Down.download("http://example.com/some image.jpg")

    assert File.exist?(tempfile.path)
  end

  def test_accepts_already_encoded_url
    stub_request(:get, "http://example.com/some%20image.jpg").to_return(body: "a" * 5)
    tempfile = Down.download("http://example.com/some%20image.jpg")

    assert File.exist?(tempfile.path)
  end

  def test_accepts_max_size
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

  def test_accepts_progresss
    stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
    size = nil
    Down.download("http://example.com/image.jpg", progress: proc { |s| size = s })

    assert_equal 5, size
  end

  def test_downloaded_files_have_original_filename_and_content_type
    stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024, headers: {'Content-Type' => 'image/jpeg'})
    tempfile = Down.download("http://example.com/image.jpg")

    assert_equal "image.jpg", tempfile.original_filename
    assert_equal "image/jpeg", tempfile.content_type

    stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5, headers: {'Content-Type' => 'image/jpeg'})
    tempfile = Down.download("http://example.com/small.jpg")

    assert_equal "small.jpg", tempfile.original_filename
    assert_equal "image/jpeg", tempfile.content_type
  end

  def test_original_filename_is_uri_decoded
    stub_request(:get, "http://example.com/image%20space.jpg").to_return(body: "a" * 20 * 1024, headers: {'Content-Type' => 'image/jpeg'})
    tempfile = Down.download("http://example.com/image%20space.jpg")

    assert_equal "image space.jpg", tempfile.original_filename
  end

  def test_original_filename_is_nil_when_path_is_missing
    stub_request(:get, "http://example.com").to_return(body: "a" * 5)
    tempfile = Down.download("http://example.com")

    assert_equal nil, tempfile.original_filename

    stub_request(:get, "http://example.com/").to_return(body: "a" * 5)
    tempfile = Down.download("http://example.com/")

    assert_equal nil, tempfile.original_filename
  end

  def test_raises_not_found_on_http_errors
    stub_request(:get, "http://example.com").to_return(status: 404)
    assert_raises(Down::NotFound) { Down.download("http://example.com") }

    stub_request(:get, "http://example.com").to_return(status: 500)
    assert_raises(Down::NotFound) { Down.download("http://example.com") }
  end

  def test_doesnt_allow_redirects
    stub_request(:get, "http://example.com").to_return(status: 301, headers: {'Location' => 'http://example2.com'})
    assert_raises(Down::NotFound) { Down.download("http://example.com") }
  end

  def test_raises_on_invalid_url
    assert_raises(Down::Error) { Down.download("http:\\example.com/image.jpg") }
  end

  def test_raises_on_invalid_scheme
    assert_raises(Down::Error) { Down.download("foo://example.com/image.jpg") }
  end

  def test_doesnt_allow_shell_execution
    assert_raises(Down::Error) { Down.download("| ls") }
  end
end

class CopyToTempfileTest < Minitest::Test
  def test_copying_to_tempfile_returns_a_tempfile
    tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))

    assert_instance_of Tempfile, tempfile
  end

  def test_copying_to_tempfile_rewinds_ios
    io = StringIO.new("foo")
    tempfile = Down.copy_to_tempfile("foo", io)

    assert_equal "foo", io.read
    assert_equal "foo", tempfile.read
  end

  def test_copying_to_tempfile_opens_in_binmode
    tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))

    assert tempfile.binmode?
  end

  def test_basename_being_a_nested_path
    tempfile = Down.copy_to_tempfile("foo/bar/baz", StringIO.new("foo"))

    assert File.exist?(tempfile.path)
  end
end
