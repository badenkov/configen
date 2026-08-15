require "did_you_mean"

class Configen::StrictOpenStruct
  def initialize(hash)
    @table = {}
    hash.each do |k, v|
      @table[k.to_sym] = v.is_a?(Hash) ? Configen::StrictOpenStruct.new(v) : v
    end
  end

  def method_missing(name, *_args)
    return @table[name] if @table.key?(name)

    suggestions = DidYouMean::SpellChecker.new(dictionary: keys.map(&:to_s)).correct(name.to_s)
    message = "Undefined variable `#{name}` in template."
    message += " Did you mean `#{suggestions.first}`?" unless suggestions.empty?
    raise NameError, message
  end

  def respond_to_missing?(name, include_private = false)
    @table.key?(name) || super
  end

  def keys
    @table.keys
  end
end
