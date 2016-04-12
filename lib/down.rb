require "open-uri"
require "tempfile"
require "fileutils"
require "cgi/util"

module Down
  class Error < StandardError; end
  class TooLarge < Error; end
  class NotFound < Error; end

  module_function

  def download(url, options = {})
    uri = URI.parse(url)

    warn "Passing :timeout option to `Down.download` is deprecated and will be removed in Down 3. You should use open-uri's :open_timeout and/or :read_timeout." if options.key?(:timeout)
    warn "Passing :progress option to `Down.download` is deprecated and will be removed in Down 3. You should use open-uri's :progress_proc." if options.key?(:progress)

    max_size = options.delete(:max_size)
    progress = options.delete(:progress)
    timeout  = options.delete(:timeout)

    downloaded_file = uri.open({
      "User-Agent" => "Down/1.0.0",
      content_length_proc: proc { |size|
        if size && max_size && size > max_size
          raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
        end
      },
      progress_proc: proc { |current_size|
        if max_size && current_size > max_size
          raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
        end
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
    raise Down::NotFound, "file not found"
  end

  def stream(url, options = {})
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)

    # taken from open-uri implementation
    if uri.is_a?(URI::HTTPS)
      require "net/https"
      http.use_ssl = true
      http.verify_mode = options[:ssl_verify_mode] || OpenSSL::SSL::VERIFY_PEER
      store = OpenSSL::X509::Store.new
      if options[:ssl_ca_cert]
        Array(options[:ssl_ca_cert]).each do |cert|
          File.directory?(cert) ? store.add_path(cert) : store.add_file(cert)
        end
      else
        store.set_default_paths
      end
      http.cert_store = store
    end

    http.start do
      req = Net::HTTP::Get.new(uri.to_s)
      http.request(req) do |response|
        content_length = response["Content-Length"].to_i if response["Content-Length"]
        response.read_body { |chunk| yield chunk, content_length }
      end
    end
  end

  def copy_to_tempfile(basename, io)
    tempfile = Tempfile.new(["down", File.extname(basename)], binmode: true)
    if io.is_a?(OpenURI::Meta) && io.is_a?(Tempfile)
      FileUtils.mv io.path, tempfile.path
    else
      IO.copy_stream(io, tempfile)
      io.rewind
    end
    tempfile.open
    tempfile
  end

  module DownloadedFile
    def original_filename
      path = base_uri.path
      path = CGI.unescape(path)
      File.basename(path) unless path.empty? || path == "/"
    end
  end
end
