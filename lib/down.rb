require "open-uri"
require "tempfile"
require "uri"
require "fileutils"

module Down
  class Error < StandardError; end
  class TooLarge < Error; end
  class NotFound < Error; end

  module_function

  def download(url, options = {})
    uri = URI.parse(url)

    max_size = options.delete(:max_size)
    progress = options.delete(:progress)
    timeout  = options.delete(:timeout)

    downloaded_file = uri.open({
      "User-Agent" => "Down/1.0.0",
      content_length_proc: proc { |size|
        raise Down::TooLarge if size && max_size && size > max_size
      },
      progress_proc: proc { |current_size|
        raise Down::TooLarge if max_size && current_size > max_size
        progress.call(current_size) if progress
      },
      read_timeout: timeout,
      redirect: false,
    }.merge(options))

    # open-uri will return a StringIO instead of a Tempfile if the filesize is
    # less than 10 KB, so if it happens we convert it back to Tempfile. We want
    # to do this with a Tempfile as well, because open-uri doesn't preserve the
    # file extension, so we want to run it against #copy_to_tempfile which
    # does.
    open_uri_file = downloaded_file
    downloaded_file = copy_to_tempfile(uri.path, open_uri_file)
    OpenURI::Meta.init downloaded_file, open_uri_file

    downloaded_file.extend DownloadedFile
    downloaded_file

  rescue => error
    raise if error.is_a?(Down::Error)
    raise Down::NotFound, error.message
  end

  def copy_to_tempfile(basename, io)
    tempfile = Tempfile.new(["down", File.extname(basename)], binmode: true)
    if io.is_a?(OpenURI::Meta) && io.is_a?(Tempfile)
      FileUtils.mv io.path, tempfile.path
    else
      IO.copy_stream(io, tempfile.path)
      io.rewind
    end
    tempfile.open
    tempfile
  end

  module DownloadedFile
    def original_filename
      path = base_uri.path
      path = URI.decode(path)
      File.basename(path) unless path.empty? || path == "/"
    end
  end
end
