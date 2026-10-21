defmodule Sprout.WorkflowsTest do
  use Sprout.DataCase

  test "demo seeds are repeatable and sensor simulation persists a fresh reading" do
    Sprout.Demo.seed!()
    Sprout.Demo.seed!()
    assert length(Sprout.Land.list_fields()) == 4
    field = hd(Sprout.Land.list_fields())
    before = Sprout.Monitoring.latest(field.id)
    assert {:ok, _} = Sprout.Monitoring.poll_field(field, Sprout.Monitoring.SimulatedAdapter)
    assert Sprout.Monitoring.latest(field.id).id > before.id
  end

  test "photo intake rejects disguised files and preserves valid originals awaiting inference" do
    Sprout.Demo.seed!()
    field = hd(Sprout.Land.list_fields())
    File.mkdir_p!("var/test-photos")

    path =
      Path.join(
        Path.expand("var/test-photos"),
        "sprout-test-#{System.unique_integer([:positive])}.png"
      )

    File.write!(path, "<script>bad</script>")
    assert {:error, :invalid_image} = Sprout.Imaging.ingest(field, path, "leaf.png")

    File.write!(
      path,
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4mQAAAAASUVORK5CYII="
      )
    )

    assert {:ok, photo} = Sprout.Imaging.ingest(field, path, "leaf.png")
    assert photo.status == :awaiting_model
    assert File.exists?(Sprout.Imaging.path(photo))
    assert {:error, :invalid_transition} = Sprout.Imaging.transition(photo, :completed, %{})
    {:ok, photo} = Sprout.Imaging.transition(photo, :processing)

    assert {:ok, %{status: :completed}} =
             Sprout.Imaging.transition(photo, :completed, %{model: "test-v1", label: "healthy"})

    File.rm!(path)
  end
end
