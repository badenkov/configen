class Configen::ERB::Template
  def initialize(template)
    @template = ERB.new(template)
  end

  def render(variables = {})
    context = Configen::ERB::TemplateContext.new(variables)
    @template.result(context.instance_eval { binding })
  end
end
