# frozen-string-literal: true

require "http"

require "down/version"
require "down/chunked_io"
require "down/errors"

require "tempfile"
require "cgi"
require "base64"

if Gem::Version.new(HTTP::VERSION) < Gem::Version.new("2.1.0")
  fail "Down requires HTTP.rb version 2.1.0 or higher"
end

module Down
  module_function

  def download(url, **options, &block)
    Http.download(url, **options, &block)
  end

  def open(url, **options, &block)
    Http.open(url, **options, &block)
  end

  module Http
    module_function

    def download(url, **options, &block)
      max_size = options.delete(:max_size)

      io = open(url, **options, rewindable: false, &block)

      if max_size && io.size && io.size > max_size
        raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
      end

      extname  = File.extname(io.data[:response].uri.path)
      tempfile = Tempfile.new(["down", extname], binmode: true)

      io.each_chunk do |chunk|
        tempfile.write(chunk)

        if max_size && tempfile.size > max_size
          raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
        end
      end

      tempfile.open # flush written content

      tempfile.extend DownloadedFile
      tempfile.url     = io.data[:response].uri.to_s
      tempfile.headers = io.data[:headers]

      tempfile
    rescue
      tempfile.close! if tempfile
      raise
    ensure
      io.close if io
    end

    def open(url, **options, &block)
      rewindable = options.delete(:rewindable)

      response = get(url, **options, &block)

      if response.code.between?(400, 599)
        raise Down::NotFound.new("file not found", response: response)
      end

      down_options = {
        chunks:   response.body.enum_for(:each),
        size:     response.content_length,
        data:     { status: response.status, headers: response.headers.to_h, response: response },
      }
      down_options[:encoding]   = response.content_type.charset if response.content_type.charset
      down_options[:on_close]   = -> { response.connection.close } unless client.persistent?
      down_options[:rewindable] = rewindable if rewindable != nil

      Down::ChunkedIO.new(down_options)
    rescue HTTP::ConnectionError,
           HTTP::Request::UnsupportedSchemeError,
           HTTP::TimeoutError
      raise Down::NotFound, "file not found"
    rescue HTTP::Redirector::TooManyRedirectsError
      raise Down::NotFound, "too many redirects"
    end

    def get(url, **options, &block)
      uri = HTTP::URI.parse(url)

      if uri.user || uri.password
        user, pass = uri.user, uri.password
        authorization = "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"
        (options[:headers] ||= {}).merge!("Authorization" => authorization)
        uri.user = uri.password = nil
      end

      client = self.client
      client = block.call(client) if block
      client.get(url, options)
    end

    def client
      Thread.current[:down_client] ||= ::HTTP.headers("User-Agent" => "Down/#{VERSION}").follow(max_hops: 2)
    end

    def client=(value)
      Thread.current[:down_client] = value
    end

    module DownloadedFile
      attr_accessor :url, :headers

      def original_filename
        filename_from_content_disposition || filename_from_url
      end

      def content_type
        content_type_header.mime_type
      end

      def charset
        content_type_header.charset
      end

      private

      def content_type_header
        ::HTTP::ContentType.parse(headers["Content-Type"])
      end

      def filename_from_content_disposition
        content_disposition = headers["Content-Disposition"].to_s
        filename = content_disposition[/filename="([^"]*)"/, 1] || content_disposition[/filename=(.+)/, 1]
        filename = CGI.unescape(filename.to_s.strip)
        filename unless filename.empty?
      end

      def filename_from_url
        path = URI(url).path
        filename = path.split("/").last
        CGI.unescape(filename) if filename
      end
    end
  end
end
