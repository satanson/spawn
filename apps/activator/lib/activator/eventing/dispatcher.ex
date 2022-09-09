defmodule Activator.Eventing.Dispatcher do
  @behaviour Activator.Dispatcher

  require Logger

  alias Eigr.Functions.Protocol.Actors.{Actor, ActorSystem}

  alias Eigr.Functions.Protocol.{
    InvocationRequest
  }

  @impl Activator.Dispatcher
  @spec dispatch(any, any, any) :: :ok | {:error, any()}
  def dispatch(data, system, actors) do
    Logger.info("Dispatching message to Actors #{inspect(actors)}")

    # case Activator.Codec.Base64.decode(data) do
    case Activator.Codec.CloudEvent.decode(data) do
      {:ok, payload} ->
        Logger.debug("Decoded event: #{inspect(payload)}")

        do_dispatch(system, actors, payload)

      {:error, error} ->
        Logger.error("Failure on decode event. Error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp do_dispatch(system, actors, payload) do
    actors
    |> Flow.from_enumerable(max_demand: System.schedulers_online())
    |> Flow.map(fn %{actor: actor, command: command} ->
      actor_type = Actor.new(name: actor)
      system_type = ActorSystem.new(name: system)

      Logger.info(
        "Request for Activate Actor [#{actor}] using command [#{command}] with payload: #{inspect(payload)}"
      )

      res =
        InvocationRequest.new(
          system: system_type,
          actor: actor_type,
          value: payload,
          command_name: command,
          async: false
        )
        |> Actors.invoke()

      Logger.info("Call result #{inspect(res)}")

      res
    end)
    |> Flow.run()
  end
end
