# frozen-string-literal: true

require "open-uri"
require "net/https"
require "addressable/uri"

require "down/backend"

require "tempfile"
require "fileutils"

module Down
  # Provides streaming downloads implemented with Net::HTTP and open-uri.
  class NetHttp < Backend
    # @rbs @options: Hash[Symbol, untyped]

    URI_NORMALIZER = -> (url) do
      addressable_uri = Addressable::URI.parse(url)
      addressable_uri.normalize.to_s
    end #: ^(String) -> String

    # Content encodings that Net::HTTP transparently decodes.
    DECODED_ENCODINGS = %w[gzip x-gzip deflate].freeze #: Array[String]
    private_constant :DECODED_ENCODINGS

    DEFAULT_OPTIONS = {
      headers:        { "User-Agent" => "Down/#{Down::VERSION}" }.freeze,
      max_redirects:  2,
      open_timeout:   30,
      read_timeout:   30,
      uri_normalizer: URI_NORMALIZER,
    }.freeze #: Hash[Symbol, untyped]

    # Initializes the backend with common defaults.
    #: (**untyped options) -> void
    def initialize(...)
      @options = merge_options(DEFAULT_OPTIONS, ...)
    end

    # Downloads a remote file to disk using open-uri. Accepts any open-uri
    # options, and a few more.
    #: (url url, destination: String, ?max_size: Integer?, ?progress_proc: (^(Integer) -> void)?, ?content_length_proc: (^(Integer?) -> void)?, ?extension: String?, ?tempfile_name: String?, ?headers: Hash[String, String], ?max_redirects: Integer, ?auth_on_redirect: bool, ?proxy: (String | URI::Generic)?, **untyped) -> nil
    #: (url url, ?destination: nil, ?max_size: Integer?, ?progress_proc: (^(Integer) -> void)?, ?content_length_proc: (^(Integer?) -> void)?, ?extension: String?, ?tempfile_name: String?, ?headers: Hash[String, String], ?max_redirects: Integer, ?auth_on_redirect: bool, ?proxy: (String | URI::Generic)?, **untyped) -> downloaded_file
    def download(url, ...)
      options = merge_options(@options, ...)

      max_size            = options.delete(:max_size)
      progress_proc       = options.delete(:progress_proc)
      content_length_proc = options.delete(:content_length_proc)
      proxy               = options.delete(:proxy)
      destination         = options.delete(:destination)
      headers             = options.delete(:headers)
      uri_normalizer      = options.delete(:uri_normalizer)
      extension           = options.delete(:extension)
      tempfile_name       = options.delete(:tempfile_name)

      # Use open-uri's :content_lenth_proc or :progress_proc to raise an
      # exception early if the file is too large.
      #
      # Also disable following redirects, as we'll provide our own
      # implementation that has the ability to limit the number of redirects.
      open_uri_options = {
        content_length_proc: proc { |size|
          if size && max_size && size > max_size
            raise Down::TooLarge, "file is too large (#{size/1024/1024}MB, max is #{max_size/1024/1024}MB)"
          end
          content_length_proc&.call(size)
        },
        progress_proc: proc { |current_size|
          if max_size && current_size > max_size
            raise Down::TooLarge, "file is too large (#{current_size/1024/1024}MB, max is #{max_size/1024/1024}MB)"
          end
          progress_proc&.call(current_size)
        },
        redirect: false,
      } #: Hash[untyped, untyped]

      # Handle basic authentication in the :proxy option.
      if proxy
        proxy    = URI(proxy)
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

      open_uri_options.merge!(options, headers)

      uri = ensure_uri(normalize_uri(url, uri_normalizer:))

      # Handle basic authentication in the remote URL.
      if uri.user || uri.password
        open_uri_options[:http_basic_authentication] ||= [uri.user, uri.password]
        uri.user = nil
        uri.password = nil
      end

      open_uri_file = open_uri(uri, **open_uri_options)

      # Handle the fact that open-uri returns StringIOs for small files.
      extname = extension ? ".#{extension}" : File.extname(open_uri_file.base_uri.path.to_s)
      tempfile = ensure_tempfile(open_uri_file, extname, tempfile_name)
      OpenURI::Meta.init tempfile, open_uri_file # add back open-uri methods
      tempfile.extend Down::NetHttp::DownloadedFile

      download_result(tempfile, destination) #: downloaded_file?
    end

    # Starts retrieving the remote file using Net::HTTP and returns an IO-like
    # object which downloads the response body on-demand.
    #: (url url, ?rewindable: bool, ?headers: Hash[String, String], ?max_redirects: Integer, ?auth_on_redirect: bool, ?proxy: (String | URI::Generic)?, **untyped) -> ChunkedIO
    def open(url, ...)
      options = merge_options(@options, ...)

      uri_normalizer = options.delete(:uri_normalizer)

      uri = ensure_uri(normalize_uri(url, uri_normalizer:))

      # Create a Fiber that halts when response headers are received.
      request = Fiber.new do
        # :max_redirects comes from DEFAULT_OPTIONS
        net_http_request(uri, **options) do |response| # steep:ignore
          Fiber.yield response
        end
      end

      response = request.resume

      response_error!(response) unless response.is_a?(Net::HTTPSuccess)

      # Build an IO-like object that will retrieve response body on-demand.
      Down::ChunkedIO.new(
        chunks:     enum_for(:stream_body, response),
        size:       content_length(response),
        encoding:   response.type_params["charset"],
        rewindable: options.fetch(:rewindable, true),
        on_close:   -> { request.resume }, # close HTTP connnection
        data: {
          status:   response.code.to_i,
          headers:  normalize_headers(response.each_header),
          response: response,
        },
      )
    end

    private

    # Calls open-uri's URI::HTTP#open method. Additionally handles redirects.
    # Receives String-keyed header kwargs alongside the options, which RBS keyword types can't express.
    #: (?) -> ((StringIO | Tempfile) & OpenURI::Meta)
    def open_uri(uri, max_redirects:, auth_on_redirect: false, **options)
      # @type var uri: URI::HTTP
      # @type var max_redirects: Integer
      # @type var auth_on_redirect: bool
      # @type var options: Hash[Symbol | String, untyped]

      uri.open(options)
    rescue OpenURI::HTTPRedirect => exception
      raise Down::TooManyRedirects, "too many redirects" if max_redirects == 0

      # fail if redirect URI scheme is not http or https
      begin
        uri = ensure_uri(exception.uri)
      rescue Down::InvalidUrl
        response = rebuild_response_from_open_uri_exception(exception)

        raise ResponseError.new("Invalid Redirect URI: #{exception.uri}", response)
      end

      # do not leak credentials on redirect
      options.delete("Authorization") unless auth_on_redirect
      options.delete(:http_basic_authentication) unless auth_on_redirect

      # forward cookies on the redirect
      if !exception.io.meta["set-cookie"].to_s.empty?
        options["Cookie"] ||= ''
        # Add new cookies avoiding duplication
        new_cookies = exception.io.meta["set-cookie"].to_s.split(';').map(&:strip)
        old_cookies = options["Cookie"].split(';')
        options["Cookie"] = (old_cookies | new_cookies).join(';')
      end

      max_redirects -= 1
      retry
    rescue OpenURI::HTTPError => exception
      response = rebuild_response_from_open_uri_exception(exception)

      # open-uri attempts to parse the redirect URI, so we re-raise that exception
      if exception.message.include?("(Invalid Location URI)")
        raise ResponseError.new("Invalid Redirect URI: #{response["Location"]}", response)
      end

      response_error!(response)
    rescue => exception
      request_error!(exception)
    end

    # Converts the given IO into a Tempfile if it isn't one already (open-uri
    # returns a StringIO when there is less than 10KB of content), and gives
    # it the specified file extension.
    #: (StringIO | Tempfile io, String extension, ?String? tempfile_name) -> Tempfile
    def ensure_tempfile(io, extension, tempfile_name = nil)
      tempfile = Tempfile.new([tempfile_name || "down-net_http", extension], binmode: true)

      if io.is_a?(Tempfile)
        # Windows requires file descriptors to be closed before files are moved
        io.close
        tempfile.close
        FileUtils.mv io.path.to_s, tempfile.path.to_s
      else
        IO.copy_stream(io, tempfile)
        io.close
      end

      tempfile.open
      tempfile
    end

    # Makes a Net::HTTP request and follows redirects.
    #: (URI::Generic uri, max_redirects: Integer, ?auth_on_redirect: bool, **untyped options) { (Net::HTTPResponse) -> void } -> void
    def net_http_request(uri, max_redirects:, auth_on_redirect: false, **options, &)
      http, request = create_net_http(uri, **options)

      begin
        response = http.start do
          http.request(request) do |resp|
            unless resp.is_a?(Net::HTTPRedirection)
              yield resp
              # In certain cases the caller wants to download only one portion
              # of the file and close the connection, so we tell Net::HTTP that
              # it shouldn't continue retrieving it.
              resp.instance_variable_set("@read", true)
            end
          end
        end
      rescue => exception
        request_error!(exception)
      end

      if response.is_a?(Net::HTTPNotModified)
        raise Down::NotModified
      elsif response.is_a?(Net::HTTPRedirection)
        raise Down::TooManyRedirects if max_redirects == 0

        # fail if redirect URI is not a valid http or https URL
        begin
          location = ensure_uri(response["Location"], allow_relative: true)
        rescue Down::InvalidUrl
          raise ResponseError.new("Invalid Redirect URI: #{response["Location"]}", response)
        end

        # do not leak credentials on redirect
        options[:headers].delete("Authorization") unless auth_on_redirect

        # handle relative redirects
        if location.relative?
          location = uri + location
          uri.user = nil unless auth_on_redirect
          uri.password = nil unless auth_on_redirect
        elsif auth_on_redirect && (uri.user || uri.password)
          # for absolute redirects, carry over URI credentials since the new location won't have them
          options[:http_basic_authentication] ||= [uri.user, uri.password]
        end

        net_http_request(location, **options, max_redirects: max_redirects - 1, auth_on_redirect:, &)
      end
    end

    # Build a Net::HTTP object for making a request.
    #: (URI::Generic uri, ?proxy: (String | URI::Generic)?, ?ssl_verify_mode: Integer?, ?ssl_ca_cert: untyped, ?read_timeout: Numeric?, ?open_timeout: Numeric?, ?headers: Hash[String, String], ?http_basic_authentication: [String?, String?]?, **untyped) -> [Net::HTTP, Net::HTTP::Get]
    def create_net_http(uri, proxy: nil, ssl_verify_mode: nil, ssl_ca_cert: nil, read_timeout: nil, open_timeout: nil, headers: {}, http_basic_authentication: nil, **)
      http_class = Net::HTTP

      if proxy
        proxy = URI(proxy)
        http_class = Net::HTTP::Proxy(proxy.hostname, proxy.port, proxy.user, proxy.password)
      end

      http = http_class.new(uri.host, uri.port)

      # Handle SSL parameters (taken from the open-uri implementation).
      if uri.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.verify_mode = ssl_verify_mode || OpenSSL::SSL::VERIFY_PEER
        store = OpenSSL::X509::Store.new
        if ssl_ca_cert
          Array(ssl_ca_cert).each do |cert|
            File.directory?(cert) ? store.add_path(cert) : store.add_file(cert)
          end
        else
          store.set_default_paths
        end
        http.cert_store = store
      end

      http.read_timeout = read_timeout
      http.open_timeout = open_timeout

      get = Net::HTTP::Get.new(uri, headers.to_h)

      user, password = http_basic_authentication || [uri.user, uri.password]
      get.basic_auth(user.to_s, password.to_s) if user || password

      [http, get]
    end

    # Yields chunks of the response body to the block.
    #: (Net::HTTPResponse response) { (String) -> void } -> void
    def stream_body(response, &)
      response.read_body(&)
    rescue => exception
      request_error!(exception)
    end

    # Returns the Content-Length, unless a Transfer-Encoding is present or
    # Net::HTTP will decode the body, in which case it doesn't reflect the
    # number of bytes read. Decoding conditions mirror Net::HTTPResponse#inflater.
    #: (Net::HTTPResponse response) -> Integer?
    def content_length(response)
      return if response["Transfer-Encoding"]

      length = response.content_length
      return length if length.nil? || length.zero?
      return if response.decode_content && !response["Content-Range"] &&
                DECODED_ENCODINGS.include?(response["Content-Encoding"]&.downcase)

      length
    end

    # Checks that the url is a valid URI and that its scheme is http or https.
    #: (untyped url) -> URI::HTTP
    #: (untyped url, allow_relative: bool) -> URI::Generic
    def ensure_uri(url, allow_relative: false)
      begin
        uri = URI(url)
      rescue URI::InvalidURIError => exception
        raise Down::InvalidUrl, exception.message
      end

      unless allow_relative && uri.relative?
        raise Down::InvalidUrl, "URL scheme needs to be http or https: #{uri}" unless uri.is_a?(URI::HTTP)
      end

      uri
    end

    # Makes sure that the URL is properly encoded.
    #: (url url, uri_normalizer: ^(untyped) -> String) -> (URI::Generic | String)
    def normalize_uri(url, uri_normalizer:)
      URI(url)
    rescue URI::InvalidURIError
      uri_normalizer.call(url)
    end

    # When open-uri raises an exception, it doesn't expose the response object.
    # Fortunately, the exception object holds response data that can be used to
    # rebuild the Net::HTTP response object.
    #: (OpenURI::HTTPError exception) -> Net::HTTPResponse
    def rebuild_response_from_open_uri_exception(exception)
      code, message = exception.io.status
      message ||= "Unknown"

      response_class = Net::HTTPResponse::CODE_TO_OBJ.fetch(code) do |c|
        Net::HTTPResponse::CODE_CLASS_TO_OBJ.fetch(c[0]) do
          Net::HTTPUnknownResponse
        end
      end
      response = response_class.new(nil, code, message)

      exception.io.metas.each do |name, values|
        values.each { |value| response.add_field(name, value) }
      end

      response
    end

    # Raises non-sucessful response as a Down::ResponseError.
    #: (Net::HTTPResponse response) -> bot
    def response_error!(response)
      code    = response.code.to_i
      message = response.message.split(" ").map(&:capitalize).join(" ")

      error_message = "#{code} #{message}"

      case response.code.to_i
      when 404      then raise Down::NotFound.new(error_message, response)
      when 400..499 then raise Down::ClientError.new(error_message, response)
      when 500..599 then raise Down::ServerError.new(error_message, response)
      else               raise Down::ResponseError.new(error_message, response)
      end
    end

    # Re-raise Net::HTTP exceptions as Down::Error exceptions.
    #: (Exception exception) -> bot
    def request_error!(exception)
      case exception
      when Net::OpenTimeout
        raise Down::TimeoutError, "timed out waiting for connection to open"
      when Net::ReadTimeout
        raise Down::TimeoutError, "timed out while reading data"
      when EOFError, IOError, SocketError, SystemCallError
        raise Down::ConnectionError, exception.message
      when OpenSSL::SSL::SSLError
        raise Down::SSLError, exception.message
      else
        raise exception
      end
    end

    # Merge default and ad-hoc options, merging nested headers.
    #: (Hash[Symbol, untyped] options, **untyped new_options) -> Hash[Symbol, untyped]
    def merge_options(options, **new_options)
      new_options[:headers] ||= {}

      options.merge(new_options) do |key, value1, value2|
        key == :headers ? value1.merge(value2) : value2
      end
    end

    # Defines some additional attributes for the returned Tempfile (on top of what
    # OpenURI::Meta already defines).
    # @rbs module-self OpenURI::Meta
    module DownloadedFile
      #: () -> String?
      def original_filename
        Utils.filename_from_content_disposition(meta["content-disposition"]) ||
        Utils.filename_from_path(base_uri.path.to_s)
      end

      #: () -> String?
      def content_type
        super unless meta["content-type"].to_s.empty?
      end
    end
  end
end
