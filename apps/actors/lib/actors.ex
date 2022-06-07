defmodule Actors do
  @moduledoc """
  Documentation for `Spawn`.
  """
  require Logger

  alias Actors.Actor.Entity, as: ActorEntity
  alias Actors.Actor.Entity.Supervisor, as: ActorEntitySupervisor

  alias Actors.Registry.ActorRegistry

  alias Eigr.Functions.Protocol.Actors.{Actor, ActorSystem, Registry}

  alias Eigr.Functions.Protocol.{
    ActorInvocation,
    ActorInvocationResponse,
    ActorSystemRequest,
    ActorSystemResponse,
    InvocationRequest,
    InvocationResponse,
    ProxyInfo,
    RegistrationRequest,
    RegistrationResponse,
    ServiceInfo
  }

  @activate_actors_min_demand 0
  @activate_actors_max_demand 4

  def register(
        %RegistrationRequest{
          service_info: %ServiceInfo{} = _service_info,
          actor_system:
            %ActorSystem{name: _name, registry: %Registry{actors: actors} = _registry} =
              actor_system
        } = registration
      ) do
    Logger.debug("Registration request received: #{inspect(registration)}")
    ActorRegistry.register(actors)
    create_actors(actor_system, actors)

    proxy_info =
      ProxyInfo.new(
        protocol_major_version: 1,
        protocol_minor_version: 2,
        proxy_name: "spawn",
        proxy_version: "0.1.0"
      )

    {:ok, RegistrationResponse.new(proxy_info: proxy_info)}
  end

  def invoke(
        %InvocationRequest{
          actor: %Actor{} = actor,
          system: %ActorSystem{} = system,
          async: type
        } = request
      ) do
    invoke(type, system, actor, request)
  end

  def invoke(
        false,
        %ActorSystem{name: system_name} = system,
        %Actor{name: actor_name} = actor,
        request
      ) do
    IO.inspect(request, label: "Requestsssssssssss")

    with {:ok, %{node: node, actor: _registered_actor}} <-
           ActorRegistry.lookup(system_name, actor_name),
         _pid <- Node.spawn(node, __MODULE__, :try_reactivate_actor, [system, actor]),
         {:ok, response_body} <- ActorEntity.invoke(actor_name, request) do
      {:ok, response_body}
    else
      {:not_found, _} ->
        Logger.error("Actor #{actor_name} not found on ActorSystem #{system_name}")
        {:error, "Actor #{actor_name} not found on ActorSystem #{system_name}"}

      {:error, reason} ->
        Logger.error(
          "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}: #{inspect(reason)}"
        )

        {:error, reason}

      _ ->
        Logger.error("Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}")
        {:error, "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}"}
    end
  end

  def invoke(
        true,
        %ActorSystem{name: system_name} = system,
        %Actor{name: actor_name} = actor,
        request
      ) do
    with {:ok, %{node: node, actor: _registered_actor}} <-
           ActorRegistry.lookup(system_name, actor_name),
         _pid <- Node.spawn(node, __MODULE__, :try_reactivate_actor, [system, actor]) do
      ActorEntity.invoke_async(actor_name, request)
    else
      {:not_found, _} ->
        Logger.error("Actor #{actor_name} not found on ActorSystem #{system_name}")
        {:error, "Actor #{actor_name} not found on ActorSystem #{system_name}"}

      {:error, reason} ->
        Logger.error(
          "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}: #{inspect(reason)}"
        )

        {:error, reason}

      _ ->
        Logger.error("Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}")
        {:error, "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}"}
    end
  end

  def try_reactivate_actor(%ActorSystem{} = system, %Actor{name: name} = actor) do
    case ActorEntitySupervisor.lookup_or_create_actor(system, actor) do
      {:ok, pid} ->
        Logger.debug("Actor #{name} reactivated. PID: #{inspect(pid)}")
        {:ok, pid}

      reason ->
        Logger.error("Failed to reactivate actor #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_actors(actor_system, actors) do
    actors
    |> Flow.from_enumerable(
      min_demand: @activate_actors_min_demand,
      max_demand: @activate_actors_max_demand
    )
    |> Flow.map(fn {actor_name, actor} ->
      Logger.debug("Registering #{actor_name} #{inspect(actor)} on Node: #{inspect(Node.self())}")

      {time, result} = :timer.tc(&lookup_actor/3, [actor_system, actor_name, actor])

      Logger.info(
        "Registered and Activated the #{actor_name} on Node #{inspect(Node.self())} in #{inspect(time)}ms"
      )

      result
    end)
    |> Flow.run()
  end

  defp lookup_actor(actor_system, actor_name, actor) do
    case ActorEntitySupervisor.lookup_or_create_actor(actor_system, actor) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        Logger.debug("Failed to register Actor #{actor_name}")
        {:error, error}
    end
  end
end
