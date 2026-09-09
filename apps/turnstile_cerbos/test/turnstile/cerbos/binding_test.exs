defmodule Turnstile.Cerbos.BindingTest do
  use ExUnit.Case, async: false

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Attributes
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.TestRepos.Sandboxed

  defmodule Pair do
    @moduledoc false
    use Ecto.Schema

    @primary_key false

    @type t :: %__MODULE__{}

    schema "turnstile_cerbos_binding_test_pairs" do
      field(:left, :string, primary_key: true)
      field(:right, :string, primary_key: true)
    end
  end

  defmodule Composite do
    @moduledoc false
    use Turnstile.Cerbos.Attributes

    resource :pair, schema: Pair do
      attribute :left, column: :left
    end
  end

  @options [repo: Sandboxed, attributes: Attributes, policies: "priv/conformance", commit: "conformance"]

  setup do
    :persistent_term.erase(Binding)
    Process.put(Binding, [])
    on_exit(fn -> :persistent_term.erase(Binding) end)
  end

  test "the binding is the repo, the declarations, the directory, and the commit" do
    assert {:ok, %Binding{} = binding} = Binding.new(@options)
    assert binding.repo == Sandboxed
    assert binding.attributes == Attributes
    assert binding.policies == "priv/conformance"
    assert binding.commit == "conformance"
    assert binding.author == nil
    assert binding.approval == nil
    assert binding.decision_log == nil

    assert Binding.to_keyword(binding) == [
             repo: Sandboxed,
             attributes: Attributes,
             policies: "priv/conformance",
             commit: "conformance",
             author: nil,
             approval: nil,
             decision_log: nil
           ]
  end

  test "options the schema does not accept are an invalid binding" do
    assert {:error, %Error.Invalid{what: :binding} = error} = Binding.new(Keyword.delete(@options, :commit))
    assert error.detail =~ "required :commit option not found"
    assert Binding.options_schema().schema[:repo][:required]
  end

  test "a module that did not declare attributes is an invalid binding" do
    assert {:error, %Error.Invalid{what: :binding} = error} = Binding.new(put_in(@options[:attributes], Folder))
    assert error.detail == "Turnstile.Fixture.Folder did not use Turnstile.Cerbos.Attributes"
  end

  test "what is bound at boot is what resolve answers, under the calling process's override" do
    assert %Binding{commit: "conformance"} = Binding.bind!(@options)
    assert {:ok, %Binding{commit: "conformance", author: nil}} = Binding.resolve()

    :ok = Binding.override(commit: "later", author: "someone")
    assert {:ok, %Binding{commit: "later", author: "someone", repo: Sandboxed}} = Binding.resolve()
  end

  test "an override around a function is put back after it" do
    _bound = Binding.bind!(@options)

    assert Binding.override([commit: "inside"], fn ->
             {:ok, binding} = Binding.resolve()
             binding.commit
           end) == "inside"

    assert {:ok, %Binding{commit: "conformance"}} = Binding.resolve()
  end

  test "an override is read from the chain of callers, nearest first" do
    :ok = Binding.override(@options)
    task = Task.async(fn -> Binding.resolve() end)

    assert {:ok, %Binding{commit: "conformance"}} = Task.await(task)
  end

  test "nothing bound and no override is an invalid binding" do
    assert Binding.resolve() == {:error, %Error.Invalid{what: :binding, detail: "nothing bound and no override"}}
  end

  test "the target of a kind is its schema and its one primary key" do
    {:ok, binding} = Binding.new(@options)

    assert Binding.target(binding, :folder) == {Folder, :id}
    assert Binding.target(binding, :nothing) == nil
    assert Binding.target(%{binding | attributes: Composite}, :pair) == nil
  end

  test "a binding that cannot be validated cannot be bound" do
    assert {:error, %Error.Invalid{}} = Binding.bind(Keyword.delete(@options, :repo))
    assert_raise Error.Invalid, fn -> Binding.bind!(Keyword.delete(@options, :repo)) end
  end
end
