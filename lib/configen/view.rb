class Configen::View < OpenStruct
  def method_missing(name, *args)
    raise NameError, "undefined template variable `#{name}`" if args.empty? && !to_h.key?(name)

    super
  end

  def respond_to_missing?(name, include_private = false)
    to_h.key?(name) || super
  end
end
