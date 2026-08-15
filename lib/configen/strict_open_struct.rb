# frozen_string_literal: true

require "did_you_mean"

# Variable tree exposed to ERB templates.
#
# Reading an undefined name raises instead of returning nil, so a typo fails the
# render rather than silently producing a broken config. Nested hashes (including
# hashes inside arrays) are wrapped recursively, so `theme.palette.bg` works at
# any depth.
#
# Only methods that cannot plausibly collide with a variable name are defined:
# `each`, `to_h`, `[]`, `dig`, `key?`, `empty?`, `keys`. Anything else goes
# through `method_missing` and is resolved as a variable.
class Configen::StrictOpenStruct
  def initialize(hash)
    @table = {}
    hash.each { |key, value| @table[key.to_sym] = self.class.wrap(value) }
  end

  def self.wrap(value)
    case value
    when Hash then new(value)
    when Array then value.map { |item| wrap(item) }
    else value
    end
  end

  def keys
    @table.keys
  end

  def key?(name)
    @table.key?(name.to_sym)
  end

  def empty?
    @table.empty?
  end

  def [](name)
    fetch_key(name.to_sym)
  end

  def each(&block)
    return @table.each unless block

    @table.each(&block)
    self
  end
  alias each_pair each

  def dig(*names)
    names.reduce(self) do |current, name|
      break nil if current.nil?
      raise NameError, "Cannot look up `#{name}` inside a non-object value." unless current.is_a?(self.class)

      current[name]
    end
  end

  def to_h
    @table.transform_values { |value| self.class.unwrap(value) }
  end

  def self.unwrap(value)
    case value
    when Configen::StrictOpenStruct then value.to_h
    when Array then value.map { |item| unwrap(item) }
    else value
    end
  end

  # `to_*`, `foo=`, `foo!` and `foo?` are never variable reads: they are Ruby
  # internals probing for conversions (`to_ary`, `to_str`) or plain typos in
  # method position, so they must raise NoMethodError rather than pretend to be
  # a missing variable.
  INTERNAL_NAME = /\A(to_|respond_to)|[=!?]\z/

  def method_missing(name, *args)
    return @table[name] if @table.key?(name)
    return super if name.to_s.match?(INTERNAL_NAME)

    fetch_key(name)
  end

  def respond_to_missing?(name, include_private = false)
    @table.key?(name) || super
  end

  private

  def fetch_key(name)
    return @table[name] if @table.key?(name)

    suggestions = DidYouMean::SpellChecker.new(dictionary: keys.map(&:to_s)).correct(name.to_s)
    message = "Undefined variable `#{name}` in template."
    message += " Did you mean `#{suggestions.first}`?" unless suggestions.empty?
    raise NameError, message
  end
end
