class Configen::ERB::Template
  def initialize(template)
    @template = ERB.new(template)
  end

  def render(variables = {})
    vars_obj = variables.is_a?(Hash) ? Configen::StrictOpenStruct.new(variables) : variables
    context = Configen::ERB::TemplateContext.new(vars_obj)
    @template.result(context.instance_eval { binding })
  end
end
