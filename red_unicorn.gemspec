$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'red_unicorn/version'

Gem::Specification.new do |s|
  s.name = 'red_unicorn'
  s.version = RedUnicorn::VERSION.to_s
  s.summary = 'Unicorn Process Handler'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/chrisroberts/red_unicorn'
  s.description = 'Unicorn Process Handler'
  s.require_path = 'lib'
  s.extra_rdoc_files = ['README.rdoc', 'CHANGELOG.rdoc']
  s.add_dependency 'unicorn', '>= 0'
  s.executables << 'red_unicorn'
  s.files = %w(README.rdoc CHANGELOG.rdoc) + Dir.glob("{bin,lib}/**/*")
end
