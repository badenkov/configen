class Configen::ERB::Template
  def initialize(template)
    @template = ERB.new(template)
  end

  def render(variables = {})
    vars_obj = variables.is_a?(Hash) ? Configen::StrictOpenStruct.new(variables) : variables
    @template.result(vars_obj.instance_eval { binding })
  end
end
