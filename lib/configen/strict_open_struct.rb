class Configen::StrictOpenStruct
  def initialize(hash)
    @table = {}
    hash.each do |k, v|
      @table[k.to_sym] = v.is_a?(Hash) ? Configen::StrictOpenStruct.new(v) : v
    end
  end

  def method_missing(name, *args, &block)
    if @table.key?(name)
      @table[name]
    else
      raise NoMethodError, "Нет такого ключа: #{name}"
    end
  end

  def respond_to_missing?(name, include_private = false)
    @table.key?(name) || super
  end

  def keys
    @table.keys
  end
end

