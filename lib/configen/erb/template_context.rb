require "did_you_mean"

class Configen::ERB::TemplateContext
  def initialize(vars_obj)
    @vars_obj = vars_obj

    # @available_variables = vars.keys(&:to_s)
    # vars.each do |key, value|
    #   define_singleton_method(key) do
    #     value
    #   end
    # end
  end

  def method_missing(name, *args, &block)
    if @vars_obj.respond_to?(name)
      @vars_obj.public_send(name, *args, &block)
    else
      available = if @vars_obj.respond_to?(:keys)
                    @vars_obj.keys.map(&:to_s)
                  else
                    @vars_obj.methods(false).map(&:to_s)
                  end

      spell_checker = DidYouMean::SpellChecker.new(dictionary: available)
      suggestions = spell_checker.correct(name.to_s)

      msg = "Undefined variable `#{name}` in template."
      msg += " Did you mean `#{suggestions.first}`?" unless suggestions.empty?

      raise NameError, msg
    end
  end

  def respond_to_missing?(name, include_all = false)
    @vars_obj.respond_to?(name) || super
  end

  private

    def sugest(name)
      DidYouMean::SpellChecker.new(dictionary: @vars_obj.keys.map(&:to_s)).correct(name.to_s)
    end
end

