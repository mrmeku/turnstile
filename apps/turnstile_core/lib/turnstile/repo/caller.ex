defmodule Turnstile.Repo.Caller do
  @moduledoc """
  The module that called the Repo, read from the calling process's stack:
  the first frame that belongs neither to the Repo nor to the seam nor to
  Ecto and the libraries beneath it. A declared exemption is recorded
  against it, and a library exemption is accepted only when it is a
  `Turnstile.*` module.
  """

  @skipped_prefixes ~w(Elixir.Ecto. Elixir.DBConnection Elixir.Postgrex) ++
                      ~w(Elixir.Enum Elixir.Stream Elixir.Task Elixir.Agent Elixir.GenServer Elixir.Process Elixir.Kernel)
  # The seam's own modules by name, so this file depends on none of them.
  @seam Enum.map(
          ~w(Repo Repo.Caller Repo.Facts Repo.Matching Repo.Mediation Repo.Seam Repo.Source),
          &("Elixir.Turnstile." <> &1)
        )

  @doc "The calling module, or `:any` when no frame qualifies."
  @spec module(repo :: module()) :: module() | :any
  def module(repo) when is_atom(repo) do
    {:current_stacktrace, frames} = Process.info(self(), :current_stacktrace)

    Enum.find_value(frames, :any, fn
      {module, _function, _arity, _location} when is_atom(module) ->
        if skipped?(module, repo), do: nil, else: module

      _frame ->
        nil
    end)
  end

  @doc "Whether a module is the library's own: `Turnstile` or under it."
  @spec library?(module() | :any) :: boolean()
  def library?(Turnstile), do: true
  def library?(:any), do: false
  def library?(module) when is_atom(module), do: String.starts_with?(Atom.to_string(module), "Elixir.Turnstile.")

  defp skipped?(module, repo) do
    name = Atom.to_string(module)

    module == repo or name in @seam or
      not String.starts_with?(name, "Elixir.") or
      Enum.any?(@skipped_prefixes, &String.starts_with?(name, &1))
  end
end
