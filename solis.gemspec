# frozen_string_literal: true

require_relative "lib/solis/version"

Gem::Specification.new do |spec|
  spec.name = "solis"
  spec.version = Solis::VERSION
  spec.authors = ["Mehmet Celik"]
  spec.email = ["mehmet@celik.be"]

  spec.summary = "Smart Ontology Layer for Interoperable Systems"
  spec.description = "Smart Ontology Layer for Interoperable Systems"
  spec.homepage = "https://github.com/mehmetc/solis"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  #spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mehmetc/solis"
  spec.metadata["changelog_uri"] = "https://github.com/mehmetc/solis"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "json", "~> 2.9"
  spec.add_dependency "linkeddata", "~> 3.3"
  spec.add_dependency "graphiti", "~> 1.7"
  spec.add_dependency "graphiti_graphql", "~> 0.1"
  spec.add_dependency "data_collector"
  spec.add_dependency "abbrev"
  spec.add_dependency "csv"
  spec.add_dependency "mutex_m"
  spec.add_dependency "ostruct"
  spec.add_dependency 'google_drive', '~> 3.0'
  spec.add_dependency 'json-ld', '~> 3.3.2'
  spec.add_dependency 'shacl', '~> 0.4.1'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
