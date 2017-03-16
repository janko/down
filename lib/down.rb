require "down/version"
require "down/chunked_io"

require "open-uri"
require "net/http"
require "tempfile"
require "fileutils"
require "cgi/util"

module Down
  class Error < StandardError; end
  class TooLarge < Error; end
  class NotFound < Error; end

  module_function

  def download(url, options = {})
    warn "Passing :timeout option to `Down.download` is deprecated and will be removed in Down 3. You should use open-uri's :open_timeout and/or :read_timeout." if options.key?(:timeout)
    warn "Passing :progress option to `Down.download` is deprecated and will be removed in Down 3. You should use open-uri's :progress_proc." if options.key?(:progress)

    max_size            = options.delete(:max_size)
    max_redirects       = options.delete(:max_redirects) || 2
    progress_proc       = options.delete(:progress_proc) || options.delete(:progress)
    content_length_proc = options.delete(:content_length_proc)
    timeout             = options.delete(:timeout)

    tries = max_redirects + 1

    begin
      uri = URI.parse(url)

      open_uri_options = {
        "User-Agent" => "Down/#{VERSION}",
        content_length_proc: proc { |size|
          if size && max_size && size > max_size
            raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
          end
          content_length_proc.call(size) if content_length_proc
        },
        progress_proc: proc { |current_size|
          if max_size && current_size > max_size
            raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
          end
          progress_proc.call(current_size) if progress_proc
        },
        read_timeout: timeout,
        redirect: false,
      }

      if uri.user || uri.password
        open_uri_options[:http_basic_authentication] = [uri.user, uri.password]
        uri.user = nil
        uri.password = nil
      end

      open_uri_options.update(options)

      downloaded_file = uri.open(open_uri_options)
    rescue OpenURI::HTTPRedirect => redirect
      url = redirect.uri.to_s
      retry if (tries -= 1) > 0
      raise Down::NotFound, "too many redirects"
    rescue => error
      raise if error.is_a?(Down::Error)
      raise Down::NotFound, "file not found"
    end

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
  end

  def stream(url, options = {})
    warn "Down.stream is deprecated and will be removed in Down 3. Use Down.open instead."
    io = open(url, options)
    io.each_chunk { |chunk| yield chunk, io.size }
    io.close
  end

  def open(url, options = {})
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

    request = Fiber.new do
      http.start do
        http.request_get(uri.request_uri) do |response|
          Fiber.yield response
          response.instance_variable_set("@read", true)
        end
      end
    end

    response = request.resume

    if response.chunked?
      # Net::HTTP's implementation of reading "Transfer-Encoding: chunked"
      # raises a Fiber error, so we work around it by downloading the whole
      # response body without Enumerators (which internally use Fibers).
      warn "Response from #{url} returned as \"Transfer-Encoding: chunked\", which Down cannot partially download, so the whole response body will be downloaded instead."

      tempfile = Tempfile.new("down", binmode: true)
      response.read_body { |chunk| tempfile << chunk }
      tempfile.rewind

      request.resume # close HTTP connection

      ChunkedIO.new(
        chunks: Enumerator.new { |y| y << tempfile.read(16*1024) until tempfile.eof? },
        size: tempfile.size,
        on_close: -> { tempfile.close! },
      )
    else
      ChunkedIO.new(
        chunks: response.enum_for(:read_body),
        size: response["Content-Length"] && response["Content-Length"].to_i,
        on_close: -> { request.resume }, # close HTTP connnection
      )
    end
  end

  def copy_to_tempfile(basename, io)
    tempfile = Tempfile.new(["down", File.extname(basename)], binmode: true)
    if io.is_a?(OpenURI::Meta) && io.is_a?(Tempfile)
      io.close
      tempfile.close
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
      filename_from_content_disposition || filename_from_uri
    end

    private

    def filename_from_content_disposition
      meta["content-disposition"].to_s[/filename="?([^ "]+)"?/, 1]
    end

    def filename_from_uri
      path = base_uri.path
      filename = path.split("/").last
      CGI.unescape(filename) if filename
    end
  end
end
