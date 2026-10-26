# frozen_string_literal: true

require "json"
require "base64"
require "zlib"
require "rack"
require "rack/auth/basic"
require "puma"
require "puma/server"

# Rack body that streams an array of chunks without Content-Length.
# Avoids Enumerator/Fiber on JRuby which can cause premature connection closes.
class StreamBody
  def initialize(chunks)
    @chunks = chunks
  end

  def each(&block)
    @chunks.each(&block)
  end

  def close; end
end

# Rack app that implements the subset of httpbin.org endpoints used in tests.
class Httpbin
  # Minimal valid 1×1 PNG image
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  ).b.freeze

  UTF8_HTML = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>UTF-8 sample &#10004;</body></html>".freeze

  def call(env)
    req = Rack::Request.new(env)
    dispatch(req)
  rescue => e
    [500, { "Content-Type" => "text/plain" }, ["#{e.class}: #{e.message}"]]
  end

  private

  def dispatch(req)
    path = req.path_info
    path = "/" if path.empty?

    case path
    when "/"
      [200, { "Content-Type" => "text/html" }, ["<html><body>httpbin compatible</body></html>"]]

    when "/get", "/post"
      json(request_info(req))

    when "/headers"
      json("headers" => extract_headers(req))

    when "/user-agent"
      json("user-agent" => req.get_header("HTTP_USER_AGENT"))

    when %r{\A/bytes/(\d+)\z}
      n = $1.to_i
      seed = req.GET["seed"]
      bytes = random_bytes(n, seed ? seed.to_i : nil)
      [200, { "Content-Type" => "application/octet-stream", "Content-Length" => n.to_s }, [bytes]]

    when %r{\A/stream-bytes/(\d+)\z}
      n = $1.to_i
      chunk_size = (req.GET["chunk_size"] || "10").to_i
      seed = req.GET["seed"]
      bytes = random_bytes(n, seed ? seed.to_i : nil)
      chunks = bytes.bytes.each_slice(chunk_size).map { |s| s.pack("C*") }
      [200, { "Content-Type" => "application/octet-stream" }, StreamBody.new(chunks)]

    when %r{\A/stream/(\d+)\z}
      n = $1.to_i
      lines = Array.new(n) { |i| "#{JSON.generate("id" => i, "url" => req.url)}\n" }
      [200, { "Content-Type" => "application/json" }, StreamBody.new(lines)]

    when "/robots.txt"
      [200, { "Content-Type" => "text/plain" }, ["User-agent: *\nDisallow: /deny\n"]]

    when "/redirect-to"
      url = req.GET["url"].to_s
      [302, { "Location" => url }, []]

    when %r{\A/redirect/(\d+)\z}
      n = $1.to_i
      target = n <= 1 ? "#{req.base_url}/get" : "#{req.base_url}/redirect/#{n - 1}"
      [302, { "Location" => target }, []]

    when %r{\A/absolute-redirect/(\d+)\z}
      n = $1.to_i
      target = n <= 1 ? "#{req.base_url}/get" : "#{req.base_url}/absolute-redirect/#{n - 1}"
      [302, { "Location" => target }, []]

    when %r{\A/relative-redirect/(\d+)\z}
      n = $1.to_i
      target = n <= 1 ? "/get" : "/relative-redirect/#{n - 1}"
      [302, { "Location" => target }, []]

    when "/response-headers"
      headers = { "Content-Type" => "application/json" }
      req.GET.each { |k, v| headers[k] = v }
      [200, headers, [JSON.generate(req.GET)]]

    when %r{\A/status/(\d+)\z}
      code = $1.to_i
      [code, { "Content-Type" => "text/plain" }, []]

    when %r{\A/basic-auth/([^/]+)/(.+)\z}
      expected_user = Rack::Utils.unescape_path($1)
      expected_pass = Rack::Utils.unescape_path($2)
      check_basic_auth(req, expected_user, expected_pass)

    when "/image/png"
      [200, { "Content-Type" => "image/png" }, [PNG]]

    when "/encoding/utf8", "/html"
      [200, { "Content-Type" => "text/html; charset=utf-8" }, [UTF8_HTML]]

    when %r{\A/delay/(\d+(?:\.\d+)?)\z}
      sleep $1.to_f
      json(request_info(req))

    when "/drip"
      [200, { "Content-Type" => "application/octet-stream" }, ["*" * 10]]

    when %r{\A/etag/(.+)\z}
      etag = Rack::Utils.unescape_path($1)
      [200, { "Content-Type" => "application/json", "ETag" => etag }, ["{}"]]

    when "/gzip"
      gzipped = Zlib.gzip(JSON.generate(request_info(req)))
      # Send chunked: split gzipped into pieces to force Transfer-Encoding: chunked
      chunks = gzipped.bytes.each_slice(50).map { |s| s.pack("C*") }
      [200, { "Content-Type" => "application/json", "Content-Encoding" => "gzip" },
       StreamBody.new(chunks)]

    # Always compresses, regardless of Accept-Encoding, and sends the
    # compressed size as Content-Length.
    when %r{\A/encoded-bytes/([^/]+)/(\d+)\z}
      encoding, body = $1, "a" * $2.to_i
      encoded = case encoding.downcase
                when "gzip", "x-gzip" then Zlib.gzip(body)
                when "deflate"        then Zlib::Deflate.deflate(body)
                else                       body
                end
      headers = { "Content-Type" => "application/octet-stream", "Content-Encoding" => encoding, "Content-Length" => encoded.bytesize.to_s }
      if req.GET["content_range"]
        headers["Content-Range"] = "bytes 0-#{encoded.bytesize - 1}/#{encoded.bytesize}"
        [206, headers, [encoded]]
      else
        [200, headers, [encoded]]
      end

    else
      [404, { "Content-Type" => "text/plain" }, ["Not Found"]]
    end
  end

  def json(data)
    [200, { "Content-Type" => "application/json" }, [JSON.generate(data)]]
  end

  def request_info(req)
    { "url" => req.url, "headers" => extract_headers(req), "args" => req.GET }
  end

  def extract_headers(req)
    headers = {}
    req.env.each do |key, value|
      next unless key.start_with?("HTTP_")
      name = key[5..].split("_").map(&:capitalize).join("-")
      headers[name] = value
    end
    headers
  end

  def random_bytes(n, seed = nil)
    rng = seed ? Random.new(seed) : Random.new
    Array.new(n) { rng.rand(256) }.pack("C*")
  end

  def check_basic_auth(req, expected_user, expected_pass)
    auth = Rack::Auth::Basic::Request.new(req.env)
    if auth.provided? && auth.basic? && auth.credentials == [expected_user, expected_pass]
      json("authenticated" => true, "user" => expected_user)
    else
      [401, { "Content-Type" => "application/json", "WWW-Authenticate" => 'Basic realm="Fake Realm"' },
       [JSON.generate("authenticated" => false)]]
    end
  end
end
