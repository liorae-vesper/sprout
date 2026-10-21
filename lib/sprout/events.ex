defmodule Sprout.Events do
  @moduledoc "Ephemeral domain notifications; subscribers reload their own read models."
  @doc """
  Broadcasts `{:farm_changed, kind}` for an `{:ok, value}` result and returns it unchanged.

  Errors pass through without notification. Broadcasts are ephemeral. Commands
  inside an explicit transaction do not broadcast: the outer transaction owner
  must publish successful results after commit. Rolled-back writes stay silent.
  """
  @spec saved(result, atom()) :: result when result: term()
  def saved({:ok, _} = result, kind) do
    unless Sprout.Repo.in_transaction?() do
      Phoenix.PubSub.broadcast(Sprout.PubSub, "farm", {:farm_changed, kind})
    end

    result
  end

  def saved(error, _), do: error
end
