require "test_helper"

require "down"
require "down/http"

require "json"

describe Down do
  i_suck_and_my_tests_are_order_dependent! # ಠ_ಠ

  describe "#backend" do
    it "returns NetHttp by default" do
      assert_equal Down::NetHttp, Down.backend
    end

    it "can set the backend via a symbol" do
      Down.backend :http
      assert_equal Down::Http, Down.backend
    end

    it "can set the backend via a class" do
      Down.backend Down::Http
      assert_equal Down::Http, Down.backend
    end
  end

  describe "#download" do
    it "delegates to the underlying backend" do
      tempfile = Down.download("#{$httpbin}/headers", headers: { "Foo" => "Bar" })
      headers = JSON.parse(tempfile.read).fetch("headers")
      assert_equal "Bar", headers.fetch("Foo")
    end
  end

  describe "#open" do
    it "delegates to the underlying backend" do
      io = Down.open("#{$httpbin}/headers", headers: { "Foo" => "Bar" })
      headers = JSON.parse(io.read).fetch("headers")
      assert_equal "Bar", headers.fetch("Foo")
    end
  end
end
