defmodule Sprout.Monitoring.FeedTest do
  use Sprout.DataCase
  import ExUnit.CaptureLog
  alias Sprout.{Demo, Land, Monitoring, TestDeviceAdapter}
  alias Sprout.Monitoring.Feed

  setup do
    Demo.seed!()
    %{fields: Land.list_fields()}
  end

  test "one device error leaves other fields live and the next poll can succeed", %{
    fields: [field | rest]
  } do
    before = Monitoring.latest(field.id)

    pid =
      start_supervised!(
        {Feed,
         adapter: TestDeviceAdapter,
         interval: 60_000,
         adapter_options: [test_pid: self(), fail_field_id: field.id, failure_mode: :controlled]}
      )

    log =
      capture_log(fn ->
        send(pid, :poll)
        assert_receive {:device_request, id, task}
        assert id == field.id
        send(task, {:reply, :error})
        _ = :sys.get_state(pid)
      end)

    assert log =~ "Sensor poll failed"
    assert Monitoring.latest(field.id).id == before.id
    for other <- rest, do: assert(Monitoring.latest(other.id).source == :device)
    send(pid, :poll)
    assert_receive {:device_request, id, task}
    assert id == field.id
    send(task, {:reply, :good})
    _ = :sys.get_state(pid)
    assert Monitoring.latest(field.id).source == :device
    assert Monitoring.latest(field.id).id > before.id
  end

  test "timeouts and crashing adapters are isolated and do not kill the polling worker" do
    for mode <- [:block, :raise, :exit] do
      pid =
        start_supervised!(
          {Feed,
           adapter: TestDeviceAdapter,
           interval: 60_000,
           timeout: 20,
           adapter_options: [test_pid: self(), mode: mode]}
        )

      log =
        capture_log(fn ->
          send(pid, :poll)
          _ = :sys.get_state(pid)
        end)

      assert log =~ "Sensor poll failed"

      _ =
        capture_log(fn ->
          send(pid, :poll)
          :sys.get_state(pid)
        end)

      stop_supervised(Feed)
    end
  end

  test "the configured timer polls without a manual trigger" do
    pid =
      start_supervised!(
        {Feed, adapter: TestDeviceAdapter, interval: 10, adapter_options: [test_pid: self()]}
      )

    assert_receive {:device_read, _, _}, 1000
    _ = :sys.get_state(pid)
    assert Enum.all?(Land.list_fields(), &(Monitoring.latest(&1.id).source == :device))
  end

  test "invalid worker configuration fails at startup" do
    assert {:error, _} = start_supervised({Feed, adapter: String})
    assert {:error, _} = start_supervised({Feed, adapter: TestDeviceAdapter, interval: 0})
    assert {:error, _} = start_supervised({Feed, adapter: TestDeviceAdapter, timeout: -1})
  end
end
