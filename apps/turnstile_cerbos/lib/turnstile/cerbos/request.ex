defmodule Turnstile.Cerbos.Request do
  @moduledoc """
  The bodies the sidecar reads: one for a decision over resources, one for a
  query plan. Both carry the principal with the attributes the declarations
  name and a role per subject kind, so a policy says which kinds it answers
  for by naming roles, and nothing else about the subject travels.

  A request body is an edge, so it is the one map here that is not a
  struct, and this module is the only place it is built.
  """

  alias Turnstile.Cerbos.Values
  alias Turnstile.Id
  alias Turnstile.Object
  alias Turnstile.Subject

  @doc """
  A decision for one operation over objects, each with the attribute values
  read for it: the body of `POST /api/check/resources`.
  """
  @spec check(Subject.t(), atom(), Values.attributes(), [{Object.t(), Values.attributes()}]) :: map()
  def check(%Subject{} = subject, operation, principal, objects)
      when is_atom(operation) and is_map(principal) and is_list(objects) do
    %{
      requestId: Id.new(),
      includeMeta: true,
      principal: principal(subject, principal),
      resources: Enum.map(objects, fn {object, attributes} -> resource(object, operation, attributes) end)
    }
  end

  @doc "A query plan for one operation over an object type: the body of `POST /api/plan/resources`."
  @spec plan(Subject.t(), atom(), atom(), Values.attributes()) :: map()
  def plan(%Subject{} = subject, operation, kind, principal)
      when is_atom(operation) and is_atom(kind) and is_map(principal) do
    %{
      requestId: Id.new(),
      includeMeta: true,
      principal: principal(subject, principal),
      resource: %{kind: Atom.to_string(kind)},
      action: Atom.to_string(operation)
    }
  end

  @doc """
  A decision body from a principal and a resource already in the shape the
  sidecar reads, which is the shape a logged request carries.
  """
  @spec logged(map(), map(), [String.t()]) :: map()
  def logged(principal, resource, actions) when is_map(principal) and is_map(resource) and is_list(actions) do
    %{requestId: Id.new(), includeMeta: true, principal: principal, resources: [%{resource: resource, actions: actions}]}
  end

  @doc "The principal as the sidecar reads it: the subject's id, its kind as a role, and its attributes."
  @spec principal(Subject.t(), Values.attributes()) :: map()
  def principal(%Subject{id: id, kind: kind}, attributes) when is_map(attributes) do
    %{id: to_string(id), roles: [Atom.to_string(kind)], attr: attributes}
  end

  defp resource(%Object{type: type, id: id}, operation, attributes) do
    %{
      resource: %{kind: Atom.to_string(type), id: to_string(id), attr: attributes},
      actions: [Atom.to_string(operation)]
    }
  end
end
