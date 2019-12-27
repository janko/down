module DeprecatedHelper
  def deprecated(description, &block)
    it "(deprecated) #{description}" do
      stdout, stderr = capture_io { instance_exec(&block) }

      print stdout

      refute_empty stderr
    end
  end
end

Minitest::Test.extend(DeprecatedHelper)
