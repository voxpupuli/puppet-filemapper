require 'puppet'
require 'mocha'

PROJECT_ROOT = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$LOAD_PATH.unshift(File.join(PROJECT_ROOT, "lib"))
$LOAD_PATH.unshift(File.join(PROJECT_ROOT, "spec", "lib"))

RSpec.configure do |config|
  config.mock_with :mocha
end
