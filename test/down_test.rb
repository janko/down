require "test_helper"

require "down"
require "down/http"

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
      Down.backend.expects(:download).with("http://example.com")
      Down.download("http://example.com")
    end
  end

  describe "#open" do
    it "delegates to the underlying backend" do
      Down.backend.expects(:open).with("http://example.com")
      Down.open("http://example.com")
    end
  end
end
