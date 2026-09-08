defmodule Turnstile.Repo do
  @moduledoc """
  The seam. `use Turnstile.Repo` after `use Ecto.Repo` overrides every
  function of `Turnstile.Repo.Surface` the repo defines, so each call passes
  the `turnstile:` option, a `Turnstile.Decision` or an exemption, to
  `Turnstile.Repo.Seam` before Ecto runs it. A query on a protected schema
  without the option raises `Turnstile.Error.Unmediated` before any SQL.

      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
        use Turnstile.Repo
      end

  ## Options

  - `role:` `:app`, the application's repo, or `:owner`, the library's own
    channel. Defaults to `:app`.

  An owner-role repo is the library's own channel: it runs migrations and
  the ledger's writes, every call on it carries the library exemption, and
  it records nothing. An application-role repo, the default, is the one
  the application queries through.
  """

  @schema NimbleOptions.new!(
            role: [
              type: {:in, [:app, :owner]},
              default: :app,
              doc: "`:app`, the application's repo, or `:owner`, the library's own channel."
            ]
          )

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Turnstile.Repo.__check_order__(__MODULE__)
      @turnstile_role Turnstile.Repo.__role__(opts)
      @turnstile_surface Turnstile.Repo.Surface.all()
      @before_compile Turnstile.Repo.Overrides

      @doc "The repo's role in Turnstile, `:app` or `:owner`, and the surface it was compiled against."
      @spec __turnstile__(:role) :: :app | :owner
      @spec __turnstile__(:surface) :: [Turnstile.Repo.Surface.entry()]
      def __turnstile__(:role), do: @turnstile_role
      def __turnstile__(:surface), do: @turnstile_surface
    end
  end

  @doc false
  @spec __check_order__(module()) :: :ok
  def __check_order__(module) do
    if Module.defines?(module, {:__adapter__, 0}) do
      :ok
    else
      raise ArgumentError, "use Turnstile.Repo must follow use Ecto.Repo in #{inspect(module)}"
    end
  end

  @doc false
  @spec __role__(keyword()) :: :app | :owner
  def __role__(opts) do
    opts
    |> NimbleOptions.validate!(@schema)
    |> Keyword.fetch!(:role)
  end
end
