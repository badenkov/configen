# frozen_string_literal: true

require_relative "lib/configen/version"

Gem::Specification.new do |spec|
  spec.name = "configen"
  spec.version = Configen::VERSION
  spec.authors = ["Alexey Badenkov"]
  spec.email = ["alexey.badenkov@gmail.com"]

  spec.summary = "Tool mvp for configs management"
  spec.description = "For configs managements"
  spec.homepage = "https://github.com/badenkov"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/badenkov"
  spec.metadata["changelog_uri"] = "https://github.com/badenkov"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.executables = %w[configen]
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "liquid", "~> 5.8.7"
  spec.add_dependency "listen", "~> 3.9.0"
  spec.add_dependency "logger"
  spec.add_dependency "ostruct"
  spec.add_dependency "thor", "~> 1.4"
  spec.add_dependency "tomlib", "~> 0.7.3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
