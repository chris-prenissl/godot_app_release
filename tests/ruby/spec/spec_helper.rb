require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

module UI
  def self.user_error!(message)
    raise "UI.user_error!: #{message}"
  end
end

def app_store_connect_api_key(**kwargs)
  kwargs
end

def default_platform(_name)
  nil
end

def platform(_name)
  yield if block_given?
end

def lane(_name, &block)
  nil
end

def desc(_text)
  nil
end

FASTFILE_PATH = File.expand_path("../../../addons/app_release/templates/Fastfile", __dir__)

RSpec.configure do |config|
  config.mock_with :rspec
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
