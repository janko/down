require "down/version"
require "down/chunked_io"

require "open-uri"
require "net/http"
require "tempfile"
require "fileutils"
require "cgi"

module Down
  class Error < StandardError; end
  class TooLarge < Error; end
  class NotFound < Error; end

  module_function

  def download(uri, options = {})
    max_size            = options.delete(:max_size)
    max_redirects       = options.delete(:max_redirects) || 2
    progress_proc       = options.delete(:progress_proc)
    content_length_proc = options.delete(:content_length_proc)

    if options[:proxy]
      proxy    = URI(options[:proxy])
      user     = proxy.user
      password = proxy.password

      if user || password
        proxy.user     = nil
        proxy.password = nil

        options[:proxy_http_basic_authentication] = [proxy.to_s, user, password]
        options.delete(:proxy)
      end
    end

    tries = max_redirects + 1

    begin
      uri = URI(uri)

      if uri.class != URI::HTTP && uri.class != URI::HTTPS
        raise URI::InvalidURIError, "url is not http nor https"
      end

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
      if (tries -= 1) > 0
        uri = redirect.uri
        retry
      else
        raise Down::NotFound, "too many redirects"
      end
    rescue OpenURI::HTTPError,
           URI::InvalidURIError,
           Errno::ECONNREFUSED,
           SocketError,
           Timeout::Error
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

  def open(uri, options = {})
    uri = URI(uri)
    http_class = Net::HTTP

    if options[:proxy]
      proxy = URI(options[:proxy])
      http_class = Net::HTTP::Proxy(proxy.hostname, proxy.port, proxy.user, proxy.password)
    end

    http = http_class.new(uri.host, uri.port)

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

    request_headers = options.select { |key, value| key.is_a?(String) }
    get = Net::HTTP::Get.new(uri.request_uri, request_headers)
    get.basic_auth(uri.user, uri.password) if uri.user || uri.password

    request = Fiber.new do
      http.start do
        http.request(get) do |response|
          Fiber.yield response
          response.instance_variable_set("@read", true)
        end
      end
    end

    response = request.resume

    raise Down::NotFound, "request returned status #{response.code} and body:\n#{response.body}" if response.code.to_i.between?(400, 599)

    chunked_io = ChunkedIO.new(
      chunks: response.enum_for(:read_body),
      size: response["Content-Length"] && response["Content-Length"].to_i,
      on_close: -> { request.resume }, # close HTTP connnection
      rewindable: options.fetch(:rewindable, true),
    )

    chunked_io.data[:status]  = response.code.to_i
    chunked_io.data[:headers] = {}

    response.each_header do |downcased_name, value|
      name = downcased_name.split("-").map(&:capitalize).join("-")
      chunked_io.data[:headers].merge!(name => value)
    end

    chunked_io
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

    def content_type
      super unless meta["content-type"].to_s.empty?
    end

    private

    def filename_from_content_disposition
      content_disposition = meta["content-disposition"].to_s
      filename = content_disposition[/filename="([^"]*)"/, 1] || content_disposition[/filename=(.+)/, 1]
      filename = CGI.unescape(filename.to_s.strip)
      filename unless filename.empty?
    end

    def filename_from_uri
      path = base_uri.path
      filename = path.split("/").last
      CGI.unescape(filename) if filename
    end
  end
end
