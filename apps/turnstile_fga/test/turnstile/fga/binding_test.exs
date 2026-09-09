defmodule Turnstile.Fga.BindingTest do
  use ExUnit.Case, async: false

  alias Turnstile.Error
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fixture.Folder
  alias Turnstile.TestRepos.Sandboxed

  @options [repo: Sandboxed, model: "priv/conformance/model.fga", mapping: Mapping]

  setup do
    :persistent_term.erase(Binding)
    Process.put(Binding, [])
    on_exit(fn -> :persistent_term.erase(Binding) end)
  end

  test "the binding is the repo, the model file, the mapping, and who stands behind it" do
    assert {:ok, %Binding{} = binding} = Binding.new(@options)
    assert binding.repo == Sandboxed
    assert binding.model == "priv/conformance/model.fga"
    assert binding.mapping == Mapping
    assert binding.author == nil
    assert binding.approval == nil

    assert Binding.to_keyword(binding) == [
             repo: Sandboxed,
             model: "priv/conformance/model.fga",
             mapping: Mapping,
             author: nil,
             approval: nil
           ]
  end

  test "options the schema does not accept are an invalid binding" do
    assert {:error, %Error.Invalid{what: :binding} = error} = Binding.new(Keyword.delete(@options, :model))
    assert error.detail =~ "required :model option not found"
    assert Binding.options_schema().schema[:repo][:required]
  end

  test "a module that is no tuple mapping is an invalid binding" do
    assert {:error, %Error.Invalid{what: :binding} = error} = Binding.new(put_in(@options[:mapping], Folder))
    assert error.detail == "Turnstile.Fixture.Folder is no Turnstile.Fga.TupleMapping"
  end

  test "what is bound at boot is what resolve answers, under the calling process's override" do
    assert %Binding{mapping: Mapping} = Binding.bind!(@options)
    assert {:ok, %Binding{mapping: Mapping, author: nil}} = Binding.resolve()

    :ok = Binding.override(model: "priv/conformance/other.fga", author: "someone")
    assert {:ok, %Binding{model: "priv/conformance/other.fga", author: "someone", repo: Sandboxed}} = Binding.resolve()
  end

  test "an override around a function is put back after it" do
    _bound = Binding.bind!(@options)

    assert Binding.override([author: "inside"], fn ->
             {:ok, binding} = Binding.resolve()
             binding.author
           end) == "inside"

    assert {:ok, %Binding{author: nil}} = Binding.resolve()
  end

  test "an override is read from the chain of callers, nearest first" do
    :ok = Binding.override(@options)
    task = Task.async(fn -> Binding.resolve() end)

    assert {:ok, %Binding{mapping: Mapping}} = Task.await(task)
  end

  test "nothing bound and no override is an invalid binding" do
    assert Binding.resolve() == {:error, %Error.Invalid{what: :binding, detail: "nothing bound and no override"}}
  end

  test "the model is the text of the file the binding names, and the body the server takes" do
    {:ok, binding} = Binding.new(@options)

    assert {:ok, text} = Binding.text(binding)
    assert text =~ "type folder"
    assert {:ok, compiled} = Binding.compiled(binding)
    assert compiled["schema_version"] == "1.1"
    assert Enum.map(compiled["type_definitions"], & &1["type"]) == ~w(user clearance folder item)
  end

  test "a model file that is not there is an invalid binding rather than a raise" do
    {:ok, binding} = Binding.new(put_in(@options[:model], "priv/conformance/absent.fga"))

    assert {:error, %Error.Invalid{what: :binding} = error} = Binding.text(binding)
    assert error.detail =~ "priv/conformance/absent.fga could not be read"
    assert {:error, %Error.Invalid{}} = Binding.compiled(binding)
  end

  test "a binding that cannot be validated cannot be bound" do
    assert {:error, %Error.Invalid{}} = Binding.bind(Keyword.delete(@options, :repo))
    assert_raise Error.Invalid, fn -> Binding.bind!(Keyword.delete(@options, :repo)) end
  end
end
