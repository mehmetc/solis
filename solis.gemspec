require_relative 'lib/solis/version'

Gem::Specification.new do |spec|
  spec.name          = 'solis'
  spec.version       = Solis::VERSION
  spec.authors       = ['Mehmet Celik']
  spec.email         = ['mehmet@celik.be']

  spec.summary       = 'Creates a SHACL, RDF, PlantUML file from a Google sheet and a layer ontop of a data store(RDBMS, Triple store)'
  spec.description   = 'The SUN in latin or is it SILOS spelled backwards. Creates a SHACL, RDF, PlantUML file from a Google sheet and a layer ontop of a data store(RDBMS, Triple store)'
  spec.homepage      = 'https://github.com/mehmetc/solis'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/mehmetc/solis'
  spec.metadata['changelog_uri'] = 'https://github.com/mehmetc/solis'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport', '~> 7.0'
  spec.add_runtime_dependency 'http', '~> 5.1'
  spec.add_runtime_dependency 'graphiti', '~> 1.3'
  spec.add_runtime_dependency 'moneta', '~> 1.4'
  spec.add_runtime_dependency 'linkeddata', '~> 3.2'
  spec.add_runtime_dependency 'google_drive', '~> 3.0'
  spec.add_runtime_dependency 'json', '~> 2.5'
  spec.add_runtime_dependency 'hashdiff', '~> 1.0'
  spec.add_runtime_dependency  'iso8601', '~> 0.13.0'
  spec.add_runtime_dependency  'connection_pool', '~> 2.2.5'
  spec.add_runtime_dependency  'uuidtools', '~> 2.2.0'
  spec.add_runtime_dependency  'dry-struct', '~> 1.2'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency  'minitest', '~> 5.15.0'

  #  spec.add_development_dependency  'rubocop'

  #  spec.add_development_dependency 'webmock'
end
