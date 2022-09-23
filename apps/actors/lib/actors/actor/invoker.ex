defmodule Actors.Actor.Invoker do
  @moduledoc """
  `Invoker` is responsible for making calls to the Host Function
  """

  alias Actors.Actor.Entity.EntityState
  alias Eigr.Functions.Protocol.ActorInvocation

  @type state :: EntityState.t()
  @type payload :: ActorInvocation.t()

  @callback invoke_host(any(), state()) ::
              {:ok, any(), state()} | {:error, any(), state()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Actors.Actor.Invoker

      defp invoke_host(payload, state) do
        {:ok, nil, state}
      end

      defoverridable Actors.Actor.Invoker
    end
  end
end
