# frozen_string_literal: true

require "test_helper"

class Configen::GeneratorTest < Minitest::Test
  def around
    Dir.mktmpdir do |dir|
      @output_dir = Pathname.new(dir)
      @generator = Configen::Generator.new(output_path: @output_dir.to_s)

      @templates = {
        "result/example.cfg" => file_fixture("templates/template.cfg.erb").to_s,
        "result/liquid.cfg" => file_fixture("templates/template.cfg.liquid").to_s,
        "result_dir" => file_fixture("templates/template_dir").to_s,
        "result1/config1" => file_fixture("templates/template1.cfg.erb").to_s,
        "result2/config2" => file_fixture("templates/template2.cfg.erb").to_s,
      }

      @generator.before pattern: 'result/*' do
        @changes << 'result will be changed'
      end
      @generator.before pattern: 'result1/*' do
        @changes << 'result1 will be changed'
      end
      @generator.before pattern: 'result2/*' do
        @changes << 'result2 will be changed'
      end
      @generator.after pattern: 'result/*' do
        @changes << 'result changed'
      end
      @generator.after pattern: 'result1/*' do
        @changes << 'result1 changed'
      end
      @generator.after pattern: 'result2/*' do
        @changes << 'result2 changed'
      end

      @variables = {
        "greeting" => "Hello, world!",
        "var1" => "Var 1",
        "var2" => "Var 2",
      }

      @changes = []
      super
    end
  end

  def test_render
    @generator.render(@templates, @variables)

    expected_path = File.join(@output_dir, "result", "example.cfg")
    expected_content = <<~EOC
    Template example

    Hello, world!
    EOC
    content = File.read(File.join(@output_dir, "result", "example.cfg"))

    assert File.exist?(expected_path)
    assert_equal expected_content, content

    assert @output_dir.join("result_dir", "file1.txt").exist?
    assert_equal(<<~EOF, File.read(File.join(@output_dir, "result_dir", "file1.txt")))
    File1

    <%= greeting %>
    EOF

    assert @output_dir.join("result_dir", "template1.txt").exist?, "Template should be rendered with filename without erb extension"
  end

  def test_render_with_errors
    templates = {
      'result_with_error.txt' => file_fixture('templates/template_with_error.cfg.erb').to_s,
      'result_with_error1.txt' => file_fixture('templates/template_with_error1.cfg.erb').to_s,
      'result.txt' => file_fixture('templates/template.cfg.erb').to_s,
    }
    variables = {
      "greeting" => "Hello, world",
      "settings" => {},
    }
    
    @generator.render(templates, variables)

    refute @output_dir.join("result_with_error.txt").exist?
    refute @output_dir.join("result.txt").exist?

    refute @generator.valid?

    expected_errors = {
      "result_with_error.txt" => ["Undefined variable `greetings` in template. Did you mean `greeting`?"],
      "result_with_error1.txt" => ["undefined method '[]' for nil"]
    }
    assert expected_errors, @generator.errors 
  end

  def test_before_callback
    @generator.before do
      @changes << "Before call"
      assert File.empty?(@output_dir)
    end
    @generator.render(@templates, @variables)

    assert_includes @changes, "Before call"
  end

  def test_callback_order
    @generator.render(@templates, @variables)

    assert_equal "result will be changed", @changes.shift
    assert_equal "result1 will be changed", @changes.shift
    assert_equal "result2 will be changed", @changes.shift
    assert_equal "result changed", @changes.shift
    assert_equal "result1 changed", @changes.shift
    assert_equal "result2 changed", @changes.shift
    assert @changes.empty?
  end

  def test_render_only_if_changed
    @generator.render(@templates, @variables)

    @changes = []
    @variables["var1"] = "New value"
    @generator.render(@templates, @variables)

    assert_equal 2, @changes.count
    assert_includes @changes.shift, 'result1 will be changed'
    assert_includes @changes.shift, 'result1 changed'
  end
end
