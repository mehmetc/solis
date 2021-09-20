require_relative 'lib/solis/version'

Gem::Specification.new do |spec|
  spec.name          = "solis"
  spec.version       = Solis::VERSION
  spec.authors       = ["Mehmet Celik"]
  spec.email         = ["mehmet@celik.be"]

  spec.summary       = %q{Creates a SHACL, RDF, PlantUML file from a Google sheet and a layer ontop of a data store(RDBMS, Triple store)}
  spec.description   = %q{The SUN in latin or is it SILOS spelled backwards. Creates a SHACL, RDF, PlantUML file from a Google sheet and a layer ontop of a data store(RDBMS, Triple store)}
  spec.homepage      = "https://github.com/mehmetc/solis"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mehmetc/solis"
  spec.metadata["changelog_uri"] = "https://github.com/mehmetc/solis"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activesupport"
  spec.add_runtime_dependency "graphiti"
  spec.add_runtime_dependency "moneta"
  spec.add_runtime_dependency "linkeddata"
  spec.add_runtime_dependency "google_drive"
  spec.add_runtime_dependency "json"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency  "minitest", "~> 5.0"

end
