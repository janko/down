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

namespace :rbs do
  desc "Generate sig/generated/ from inline RBS comments in lib/"
  task :generate do
    rm_rf "sig/generated"
    sh "rbs-inline", "--opt-out", "--output=sig/generated", "lib"
  end
end

desc "Type check lib/ with Steep"
task :steep => "rbs:generate" do
  sh "steep", "check"
end
