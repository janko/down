# frozen-string-literal: true

require "down/version"
require "down/net_http" unless Down.respond_to?(:download)
