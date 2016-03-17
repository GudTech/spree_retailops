source 'https://rubygems.org'

spree_version = case (ENV["SPREE_VERSION"] || "default")
when "default"
  "~> 2.2.1"
else
  "~> #{ENV["SPREE_VERSION"]}"
end

gem 'rails'
gem 'spree_core', spree_version
gem 'spree_api', spree_version
gem 'spree_auth_devise', github: 'spree/spree_auth_devise', branch: '2-2-stable'

gemspec
