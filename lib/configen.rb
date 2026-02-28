# frozen_string_literal: true

module Configen
  class Error < StandardError; end
end

require "pathname"
require "erb"
require "ostruct"
require "thor"
require "yaml"
require "fileutils"

require_relative "configen/version"
require_relative "configen/strict_open_struct"

module Configen::ERB; end
require_relative "configen/erb/template_context"
require_relative "configen/erb/template"
require_relative "configen/config"
require_relative "configen/generator"
require_relative "configen/command"
require_relative "configen/cli"
