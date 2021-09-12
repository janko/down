require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  test_files = FileList['test/**/*_test.rb']
  test_files -= ["test/wget_test.rb"] if RUBY_ENGINE == "jruby"
  t.test_files = test_files
  t.warning = true
end

task :default => :test
