require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
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
