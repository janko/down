require "bundler/setup"

require_relative "support/warnings"

ENV["MT_NO_EXPECTATIONS"] = "1"

require "minitest"
require "minitest/spec"
require "minitest/pride"

# Mocha still references the old constant
MiniTest = Minitest unless defined?(MiniTest)
require "mocha/minitest"


require "http"
require "rack"

# On JRuby, http.rb parses responses with llhttp-ffi, whose callbacks can get
# garbage collected while the parser still calls them, which intermittently
# fails requests with "couldn't read response headers". Keep the callbacks
# referenced until it's fixed upstream (https://github.com/bryanp/llhttp/issues/42).
if RUBY_ENGINE == "jruby"
  require "llhttp"

  LLHttp::Callbacks.prepend(Module.new do
    def []=(name, value)
      if value.is_a?(Proc)
        signature = LLHttp::Parser::CALLBACKS.include?(name) ? [:int, []] : [:void, [:pointer, :size_t]]
        value = FFI::Function.new(*signature, &value)
        (@functions ||= []) << value
      end

      super
    end
  end)
end
require_relative "support/httpbin"

# Pick a random available port
sock = TCPServer.new("localhost", 0)
port = sock.addr[1]
sock.close

$httpbin = "http://localhost:#{port}"

# Start the httpbin Rack app on Puma in a background thread
puma = Puma::Server.new(Httpbin.new)
puma.add_tcp_listener("localhost", port)
puma.run

# Wait for the server to accept connections
30.times do
  begin
    HTTP.timeout(connect: 0.5, write: 0.5, read: 0.5).get($httpbin)
    break
  rescue HTTP::ConnectionError, HTTP::TimeoutError
    sleep 0.1
  end
end

Minitest.autorun
