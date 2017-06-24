# frozen-string-literal: true

require "open-uri"
require "net/http"

require "down/backend"

require "tempfile"
require "fileutils"
require "cgi"

module Down
  class NetHttp < Backend
    def initialize(options = {})
      @options = options
    end

    def download(uri, options = {})
      options = @options.merge(options)

      max_size            = options.delete(:max_size)
      max_redirects       = options.delete(:max_redirects) || 2
      progress_proc       = options.delete(:progress_proc)
      content_length_proc = options.delete(:content_length_proc)

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

      if options[:proxy]
        proxy    = URI(options.delete(:proxy))
        user     = proxy.user
        password = proxy.password

        if user || password
          proxy.user     = nil
          proxy.password = nil

          open_uri_options[:proxy_http_basic_authentication] = [proxy.to_s, user, password]
        else
          open_uri_options[:proxy] = proxy.to_s
        end
      end

      open_uri_options.merge!(options)

      tries = max_redirects + 1

      begin
        uri = URI(uri)

        if uri.class != URI::HTTP && uri.class != URI::HTTPS
          raise Down::InvalidUrl, "URL scheme needs to be http or https"
        end

        if uri.user || uri.password
          open_uri_options[:http_basic_authentication] ||= [uri.user, uri.password]
          uri.user = nil
          uri.password = nil
        end

        downloaded_file = uri.open(open_uri_options)
      rescue OpenURI::HTTPRedirect => exception
        if (tries -= 1) > 0
          uri = exception.uri

          if !exception.io.meta["set-cookie"].to_s.empty?
            open_uri_options["Cookie"] = exception.io.meta["set-cookie"]
          end

          retry
        else
          raise Down::TooManyRedirects, "too many redirects"
        end
      rescue OpenURI::HTTPError => exception
        code, message = exception.io.status
        response_class = Net::HTTPResponse::CODE_TO_OBJ.fetch(code)
        response = response_class.new(nil, code, message)
        exception.io.metas.each do |name, values|
          values.each { |value| response.add_field(name, value) }
        end

        response_error!(response)
      rescue => exception
        request_error!(exception)
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
      options = @options.merge(options)

      begin
        uri = URI(uri)
        if uri.class != URI::HTTP && uri.class != URI::HTTPS
          raise Down::InvalidUrl, "URL scheme needs to be http or https"
        end
      rescue URI::InvalidURIError
        raise Down::InvalidUrl, "URL was invalid"
      end

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

      http.read_timeout = options[:read_timeout] if options.key?(:read_timeout)
      http.open_timeout = options[:open_timeout] if options.key?(:open_timeout)

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

      begin
        response = request.resume

        response_error!(response) unless (200..299).cover?(response.code.to_i)
      rescue => exception
        request_error!(exception)
      end

      Down::ChunkedIO.new(
        chunks:     response.enum_for(:read_body),
        size:       response["Content-Length"] && response["Content-Length"].to_i,
        encoding:   response.type_params["charset"],
        rewindable: options.fetch(:rewindable, true),
        on_close:   -> { request.resume }, # close HTTP connnection
        data: {
          status:   response.code.to_i,
          headers:  response.each_header.inject({}) { |headers, (downcased_name, value)|
                      name = downcased_name.split("-").map(&:capitalize).join("-")
                      headers.merge!(name => value)
                    },
          response: response,
        },
      )
    end

    private

    def copy_to_tempfile(basename, io)
      tempfile = Tempfile.new(["down-net_http", File.extname(basename)], binmode: true)
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

    def response_error!(response)
      code    = response.code.to_i
      message = response.message.split(" ").map(&:capitalize).join(" ")

      args = ["#{code} #{message}", response: response]

      case response.code.to_i
      when 400..499 then raise Down::ClientError.new(*args)
      when 500..599 then raise Down::ServerError.new(*args)
      else               raise Down::ResponseError.new(*args)
      end
    end

    def request_error!(exception)
      case exception
      when URI::InvalidURIError
        raise Down::InvalidUrl, "URL was invalid"
      when Errno::ECONNREFUSED
        raise Down::ConnectionError, "connection was refused"
      when EOFError,
           IOError,
           Errno::ECONNABORTED,
           Errno::ECONNRESET,
           Errno::EPIPE,
           Errno::EINVAL,
           Errno::EHOSTUNREACH
        raise Down::ConnectionError, exception.message
      when SocketError
        raise Down::ConnectionError, "domain name could not be resolved"
      when Errno::ETIMEDOUT,
           Timeout::Error,
           Net::OpenTimeout,
           Net::ReadTimeout
        raise Down::TimeoutError, "request timed out"
      when defined?(OpenSSL) && OpenSSL::SSL::SSLError
        raise Down::SSLError, exception.message
      else
        raise exception
      end
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
end
