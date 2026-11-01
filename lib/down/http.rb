# frozen-string-literal: true

gem "http", ">= 2.1.0", "< 7"

require "http"
require "addressable/uri"

require "down/backend"

require "tempfile"

module Down
  # Provides streaming downloads implemented with HTTP.rb.
  class Http < Backend
    # @rbs @method: HTTP::verb | String
    # @rbs @client: HTTP::Session | HTTP::Client

    # Initializes the backend with common defaults.
    #: (?method: HTTP::verb | String, **untyped options) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> void
    def initialize(method: :get, **options, &block)
      @method = method
      @client = HTTP
        .headers("User-Agent" => "Down/#{Down::VERSION}")
        .follow(max_hops: 2)
        .timeout(connect: 30, write: 30, read: 30)

      if options.any?
        client_class = defined?(HTTP::Session) ? HTTP::Session : HTTP::Client
        @client = client_class.new(@client.default_options.merge(options))
      end
      @client = block.call(@client) if block
    end

    # Downlods the remote file to disk. Accepts HTTP.rb options via a hash or a
    # block, and some additional options as well.
    #: (url url, destination: String, ?max_size: Integer?, ?progress_proc: (^(Integer) -> void)?, ?content_length_proc: (^(Integer) -> void)?, ?extension: String?, ?tempfile_name: String?, **untyped) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> nil
    #: (url url, ?destination: nil, ?max_size: Integer?, ?progress_proc: (^(Integer) -> void)?, ?content_length_proc: (^(Integer) -> void)?, ?extension: String?, ?tempfile_name: String?, **untyped) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> downloaded_file
    def download(url, max_size: nil, progress_proc: nil, content_length_proc: nil, destination: nil, extension: nil, tempfile_name: nil, **, &)
      response = request(url, **, &)

      content_length = response.content_length

      content_length_proc&.call(content_length) if content_length

      if max_size && content_length && content_length > max_size
        raise Down::TooLarge, "file is too large (#{content_length/1024/1024}MB, max is #{max_size/1024/1024}MB)"
      end

      extname  = extension ? ".#{extension}" : File.extname(response.uri.path)
      tempfile = Tempfile.new([tempfile_name || "down-http", extname], binmode: true)

      stream_body(response) do |chunk|
        tempfile.write(chunk)
        chunk.clear # deallocate string

        progress_proc&.call(tempfile.size)

        if max_size && tempfile.size > max_size
          raise Down::TooLarge, "file is too large (#{tempfile.size/1024/1024}MB, max is #{max_size/1024/1024}MB)"
        end
      end

      tempfile.open # flush written content

      tempfile = tempfile.extend(Down::Http::DownloadedFile) #: Tempfile & Down::Http::DownloadedFile
      tempfile.url     = response.uri.to_s
      tempfile.headers = normalize_headers(response.headers.to_h)

      download_result(tempfile, destination) #: downloaded_file?
    rescue
      tempfile&.close!
      raise
    end

    # Starts retrieving the remote file and returns an IO-like object which
    # downloads the response body on-demand. Accepts HTTP.rb options via a hash
    # or a block.
    #: (url url, ?rewindable: bool, **untyped) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> ChunkedIO
    def open(url, rewindable: true, **, &)
      response = request(url, **, &)

      Down::ChunkedIO.new(
        chunks:     enum_for(:stream_body, response),
        size:       response.content_length,
        encoding:   response.content_type.charset,
        rewindable: rewindable,
        data:       {
          status:   response.code,
          headers:  normalize_headers(response.headers.to_h),
          response: response
        },
      )
    end

    private

    #: (url url, ?method: HTTP::verb | String, **untyped) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> HTTP::Response
    def request(url, method: @method, **, &)
      response = send_request(method, url, **, &)
      response_error!(response) unless response.status.success?
      response
    end

    #: (HTTP::verb | String method, url url, **untyped) ?{ ((HTTP::Session | HTTP::Client)) -> (HTTP::Session | HTTP::Client) } -> HTTP::Response
    def send_request(method, url, **, &block)
      uri = HTTP::URI.parse(url)

      client = @client
      client = client.basic_auth(user: uri.user.to_s, pass: uri.password.to_s) if uri.user || uri.password
      client = block.call(client) if block

      client.request(method, url, **)
    rescue => exception
      request_error!(exception)
    end

    # Yields chunks of the response body to the block.
    #: (HTTP::Response response) { (String) -> void } -> void
    def stream_body(response, &)
      response.body.each(&)
    rescue => exception
      request_error!(exception)
    ensure
      response.connection&.close unless @client.persistent?
    end

    # Raises non-sucessful response as a Down::ResponseError.
    #: (HTTP::Response response) -> bot
    def response_error!(response)
      message = response.status.to_s

      case response.code
      when 404      then raise Down::NotFound.new(message, response)
      when 400..499 then raise Down::ClientError.new(message, response)
      when 500..599 then raise Down::ServerError.new(message, response)
      else               raise Down::ResponseError.new(message, response)
      end
    end

    # Re-raise HTTP.rb exceptions as Down::Error exceptions.
    #: (Exception exception) -> bot
    def request_error!(exception)
      case exception
      when HTTP::Request::UnsupportedSchemeError, Addressable::URI::InvalidURIError, *invalid_url_errors
        raise Down::InvalidUrl, exception.message
      when HTTP::ConnectionError
        raise Down::ConnectionError, exception.message
      when HTTP::TimeoutError
        raise Down::TimeoutError, exception.message
      when HTTP::Redirector::TooManyRedirectsError
        raise Down::TooManyRedirects, exception.message
      when OpenSSL::SSL::SSLError
        raise Down::SSLError, exception.message
      else
        raise exception
      end
    end

    #: () -> Array[singleton(Exception)]
    def invalid_url_errors
      defined?(HTTP::URI::InvalidError) ? [HTTP::URI::InvalidError] : []
    end

    # Defines some additional attributes for the returned Tempfile.
    module DownloadedFile
      attr_accessor :url #: String
      attr_accessor :headers #: Hash[String, untyped]

      #: () -> String?
      def original_filename
        Utils.filename_from_content_disposition(headers["Content-Disposition"]) ||
        Utils.filename_from_path(HTTP::URI.parse(url).path)
      end

      #: () -> String?
      def content_type
        HTTP::ContentType.parse(headers["Content-Type"]).mime_type
      end

      #: () -> String?
      def charset
        HTTP::ContentType.parse(headers["Content-Type"]).charset
      end
    end
  end
end
