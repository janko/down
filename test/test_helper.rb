require "bundler/setup"

ENV["MT_NO_EXPECTATIONS"] = "1"

require "minitest"
require "minitest/spec"
require "minitest/pride"

# Mocha still references the old constant
MiniTest = Minitest unless defined?(MiniTest)
require "mocha/minitest"

require_relative "support/deprecated_helper"
require_relative "support/warnings"

require "http"
require "rack"
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
