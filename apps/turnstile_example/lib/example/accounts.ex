defmodule Example.Accounts do
  @moduledoc """
  Accounts and the roles they hold: assignments to programs, roles in
  offices, and the override permission. Role administration is not itself
  a rule of the example, so its writes carry a declared exemption naming
  it; every read of a role by a rule happens inside the adapter at check
  time, and a revocation deletes nothing but the role row.

  A grant to many accounts at once goes through `Turnstile.Facts`, which
  records one event per assignment; a plain `insert_all` on a fact schema is
  refused where a ledger is configured.
  """

  import Ecto.Query, only: [from: 2]

  alias Example.AccountRole
  alias Example.Assignment
  alias Example.OfficeRole
  alias Example.Repo
  alias Example.User
  alias Turnstile.Error
  alias Turnstile.Facts
  alias Turnstile.Facts.Record
  alias Turnstile.Subject

  @administration {:exempt, "role administration: no rule of the example governs who grants roles"}

  @doc "The subject for an account id: its kind is the account's, or `nil` when there is no such account."
  @spec subject(String.t(), String.t() | nil) :: Subject.t() | nil
  def subject(user_id, session_id \\ nil) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      %User{kind: kind} -> %Subject{id: user_id, kind: kind, session_id: session_id}
      nil -> nil
    end
  end

  @doc "Assign an account to a program with a role."
  @spec assign(String.t(), integer(), :lead | :member) :: Assignment.t()
  def assign(user_id, program_id, role) when is_binary(user_id) and role in [:lead, :member] do
    Repo.insert!(%Assignment{user_id: user_id, program_id: program_id, role: role}, turnstile: @administration)
  end

  @doc """
  Assign many accounts to a program with one role, as one write: one audit
  record and one fact event per assignment, sharing an operation id.
  """
  @spec assign_all([String.t()], integer(), :lead | :member) :: {:ok, Record.t()} | {:error, Error.Engine.t()}
  def assign_all(user_ids, program_id, role) when is_list(user_ids) and role in [:lead, :member] do
    entries = Enum.map(user_ids, &%{user_id: &1, program_id: program_id, role: role})
    Facts.bulk_insert(Assignment, entries, repo: Repo, turnstile: @administration)
  end

  @doc """
  Revoke an account's assignment to a program, one row at a time so the
  ledger receives the revocation. Returns the number of rows removed.
  """
  @spec unassign(String.t(), integer()) :: non_neg_integer()
  def unassign(user_id, program_id) when is_binary(user_id) do
    query = from(a in Assignment, where: a.user_id == ^user_id and a.program_id == ^program_id)

    query
    |> Repo.all(turnstile: @administration)
    |> Enum.map(&Repo.delete!(&1, turnstile: @administration))
    |> length()
  end

  @doc "Give an account a role in an office."
  @spec office_role(String.t(), integer(), :designator | :approver) :: OfficeRole.t()
  def office_role(user_id, office_id, role) when is_binary(user_id) and role in [:designator, :approver] do
    Repo.insert!(%OfficeRole{user_id: user_id, office_id: office_id, role: role}, turnstile: @administration)
  end

  @doc "Grant the override permission to an account."
  @spec grant_override(String.t()) :: AccountRole.t()
  def grant_override(user_id) when is_binary(user_id) do
    Repo.insert!(%AccountRole{user_id: user_id, role: :override}, turnstile: @administration)
  end

  @doc "Whether the account holds the override permission."
  @spec override_permitted?(String.t()) :: boolean()
  def override_permitted?(user_id) when is_binary(user_id) do
    query = from(r in AccountRole, where: r.user_id == ^user_id and r.role == :override)
    Repo.exists?(query)
  end

  @doc "Change an account's employment; the next check sees it."
  @spec set_employment(String.t(), :federal | :contractor) :: User.t()
  def set_employment(user_id, employment) when is_binary(user_id) and employment in [:federal, :contractor] do
    user = Repo.get!(User, user_id)
    Repo.update!(Ecto.Changeset.change(user, employment: employment), turnstile: @administration)
  end

  @doc "Correct an account's nationality; the next check sees it."
  @spec set_nationality(String.t(), String.t()) :: User.t()
  def set_nationality(user_id, nationality) when is_binary(user_id) and is_binary(nationality) do
    user = Repo.get!(User, user_id)
    Repo.update!(Ecto.Changeset.change(user, nationality: nationality), turnstile: @administration)
  end

  @doc "Every privileged account with the roles it holds, by account id."
  @spec privileged() :: [{User.t(), [atom()]}]
  def privileged do
    query =
      from(u in User,
        where: u.kind == :privileged,
        left_join: r in AccountRole,
        on: r.user_id == u.id,
        order_by: [u.id, r.role],
        select: {u, r.role}
      )

    query
    |> Repo.all()
    |> Enum.group_by(fn {user, _role} -> user end, fn {_user, role} -> role end)
    |> Enum.map(fn {user, roles} -> {user, Enum.reject(roles, &is_nil/1)} end)
    |> Enum.sort_by(fn {user, _roles} -> user.id end)
  end
end
