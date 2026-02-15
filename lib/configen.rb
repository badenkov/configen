# frozen_string_literal: true

module Configen
  class Error < StandardError; end
end

require "tmpdir"
require "pathname"
require "erb"
require "ostruct"
require "thor"
require "json"
require "yaml"
require "fileutils"
require "digest"
require "tomlib"

require_relative "configen/version"
require_relative "configen/strict_open_struct"

module Configen::ERB; end
require_relative "configen/erb/template_context"
require_relative "configen/erb/template"
require_relative "configen/config"
require_relative "configen/variables"
require_relative "configen/generator"
require_relative "configen/environment"
require_relative "configen/view"
require_relative "configen/cli"
