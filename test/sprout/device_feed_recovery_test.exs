defmodule Sprout.Monitoring.FeedRecoveryTest do
  use Sprout.DataCase, async: true
  import ExUnit.CaptureLog
  alias Ecto.Adapters.SQL.Sandbox
  alias Sprout.{Demo, Land, Monitoring, Repo, TestDeviceAdapter}
  alias Sprout.Monitoring.Feed

  test "database unavailability is logged and the same worker resumes after access returns" do
    Demo.seed!()
    field = hd(Land.list_fields())
    before = Monitoring.latest(field.id)

    pid =
      start_supervised!(
        {Feed, adapter: TestDeviceAdapter, interval: 60_000, adapter_options: [test_pid: self()]}
      )

    log =
      capture_log(fn ->
        send(pid, :poll)
        _ = :sys.get_state(pid)
      end)

    assert log =~ "Sensor polling unavailable"
    assert Monitoring.latest(field.id).id == before.id
    Sandbox.allow(Repo, self(), pid)
    send(pid, :poll)
    _ = :sys.get_state(pid)
    assert Monitoring.latest(field.id).source == :device
    assert Monitoring.latest(field.id).id > before.id
  end
end
