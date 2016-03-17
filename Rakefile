require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
require 'spree/testing_support/extension_rake'

RSpec::Core::RakeTask.new

task :default do
  if Dir["spec/dummy"].empty?
    Rake::Task[:test_app].invoke
    Dir.chdir("../../")
  end

  gem_root = File.dirname(__FILE__)
  devise_initializer_path = Pathname.new(gem_root).join("spec/dummy/config/initializers/devise.rb")
  if !File.exist?(devise_initializer_path)
    File.open(devise_initializer_path, "w") do |f|
      f.puts "Devise.secret_key = '#{SecureRandom.hex(32)}'"
    end
  end

  Rake::Task[:spec].invoke
end

desc 'Generates a dummy app for testing'
task :test_app do
  ENV['LIB_NAME'] = 'spree_retailops'
  Rake::Task['extension:test_app'].invoke
end
