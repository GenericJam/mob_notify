defmodule MobNotify.FcmEnvelopeTest do
  # MobFcmEnvelope (priv/native/android/MobNotifyBridge.kt) turns what FCM hands
  # the app into the JSON envelope mob's router decodes. These tests compile the
  # real bridge file on the host JVM, run the envelope builder, and decode its
  # output with mob's own Mob.Notification.decode/1 — the map a screen gets in
  # {:notification, map}.
  use ExUnit.Case, async: true

  @moduletag :kotlin_host
  @moduletag timeout: 300_000

  @plugin_dir Path.expand("..", __DIR__)

  setup_all do
    {:ok, tc} = MobNotify.KotlinHost.toolchain()
    tmp = Path.join(System.tmp_dir!(), "mob_notify_kotlin_#{System.unique_integer([:positive])}")
    gen = Path.join(tmp, "gen")
    out = Path.join(tmp, "classes")
    File.mkdir_p!(gen)
    on_exit(fn -> File.rm_rf!(tmp) end)

    # The io.mob.plugin seam exactly as mob_dev generates it into a host app.
    File.write!(Path.join(gen, "MobNotifyHub.kt"), MobDev.NativeBuild.__notify_hub_kotlin__())

    File.write!(
      Path.join(gen, "MobActivityAware.kt"),
      MobDev.NativeBuild.__activity_aware_kotlin__()
    )

    {:ok, manifest} = MobDev.Plugin.Manifest.load(@plugin_dir)

    sources =
      [Path.join(@plugin_dir, manifest.android.bridge_kt)] ++
        Path.wildcard(Path.join(__DIR__, "kotlin/**/*.kt")) ++
        Path.wildcard(Path.join(gen, "*.kt"))

    {output, status} =
      System.cmd(
        tc.kotlinc,
        sources ++ ["-cp", tc.android_jar, "-d", out, "-nowarn"],
        stderr_to_stdout: true
      )

    assert status == 0, "kotlinc failed:\n#{output}"

    %{tc: tc, out: out, tmp: tmp, manifest: manifest}
  end

  # Runs the calls through MobFcmEnvelope and decodes each envelope; a "tap"
  # call's result is %{envelope: decoded | nil, copied_extras: boolean}.
  defp run(ctx, calls) do
    input = Path.join(ctx.tmp, "calls_#{System.unique_integer([:positive])}.json")
    File.write!(input, JSON.encode!(calls))

    {output, 0} =
      System.cmd(
        ctx.tc.kotlin,
        [
          "-cp",
          Enum.join([ctx.out, ctx.tc.json_jar], ":"),
          "io.mob.notify.test.MobFcmEnvelopeRunnerKt",
          input
        ],
        stderr_to_stdout: true
      )

    output
    |> String.trim()
    |> String.split("\n")
    |> List.last()
    |> JSON.decode!()
    |> Enum.map(fn
      %{"envelope" => envelope, "copiedExtras" => copied} ->
        %{envelope: decode(envelope), copied_extras: copied}

      envelope ->
        decode(envelope)
    end)
  end

  defp decode(nil), do: nil

  defp decode(json) do
    {:ok, notification} = Mob.Notification.decode(json)
    notification
  end

  # What a tap on a notification the system tray showed for FCM puts in the
  # launcher activity's extras: the sender's data plus FCM's own keys.
  @tray_extras %{
    "google.message_id" => "0:1727790000000000%abc",
    "google.sent_time" => 1_727_790_000_000,
    "google.ttl" => 2_419_200,
    "google.original_priority" => "high",
    "google.delivered_priority" => "high",
    "from" => "123456789",
    "collapse_key" => "com.mob.pushlab",
    "thread" => "42",
    "kind" => "reply"
  }

  describe "a tap on a notification the system tray showed" do
    test "becomes one :tap with the sender's data and the message id", ctx do
      assert [%{envelope: notification}] = run(ctx, [%{fn: "tap", extras: @tray_extras}])

      assert notification == %{
               presentation: :tap,
               action: "default",
               source: :push,
               id: "0:1727790000000000%abc",
               title: nil,
               body: nil,
               data: %{thread: "42", kind: "reply"}
             }
    end

    test "is left to MainActivity when it carries mob_push's mob_notification_json", ctx do
      # MainActivity delivers mob_notification_json itself; delivering here too
      # would make the tap arrive twice.
      extras = Map.put(@tray_extras, "mob_notification_json", ~s({"title":"t","body":"b"}))
      assert [%{envelope: nil}] = run(ctx, [%{fn: "tap", extras: extras}])
    end

    test "launch extras that are not an FCM tap deliver nothing and aren't copied", ctx do
      # Every resume checks the activity's intent; only a tray tap reads (and
      # so unparcels) the rest of the extras another app may have put there.
      assert [no_id, empty_id, mob_json] =
               run(ctx, [
                 %{fn: "tap", extras: %{"mob_node_suffix" => "a", "thread" => "1"}},
                 %{fn: "tap", extras: %{"google.message_id" => ""}},
                 %{fn: "tap", extras: Map.put(@tray_extras, "mob_notification_json", "{}")}
               ])

      for result <- [no_id, empty_id, mob_json] do
        assert result == %{envelope: nil, copied_extras: false}
      end
    end
  end

  describe "a message MobFirebaseService receives" do
    @mob_push_data %{
      "thread" => "42",
      "mob_notification_json" =>
        ~s({"title":"New reply","body":"Hi \\"there\\"","source":"push","data":{"thread":"42"}})
    }

    test "a mob_push message arriving in the foreground is a :foreground arrival", ctx do
      assert [notification] =
               run(ctx, [
                 %{
                   fn: "fromMessage",
                   messageId: "0:m1",
                   title: "New reply",
                   body: ~s(Hi "there"),
                   data: @mob_push_data,
                   presentation: "foreground"
                 }
               ])

      assert notification == %{
               presentation: :foreground,
               action: nil,
               source: :push,
               id: "0:m1",
               title: "New reply",
               body: ~s(Hi "there"),
               data: %{thread: "42"}
             }
    end

    test "the banner it shows taps as a :tap of the same notification", ctx do
      assert [notification] =
               run(ctx, [
                 %{
                   fn: "fromMessage",
                   messageId: "0:m1",
                   title: "New reply",
                   body: "x",
                   data: @mob_push_data,
                   presentation: "tap"
                 }
               ])

      assert %{presentation: :tap, action: "default", id: "0:m1", title: "New reply"} =
               notification

      assert notification.data == %{thread: "42"}
    end

    test "a message from another sender carries its data keys, not FCM's", ctx do
      assert [data_only, with_notification] =
               run(ctx, [
                 %{
                   fn: "fromMessage",
                   messageId: "0:m2",
                   title: nil,
                   body: nil,
                   data: %{"kind" => "sync", "from" => "123", "google.c.a.e" => "1"},
                   presentation: "foreground"
                 },
                 %{
                   fn: "fromMessage",
                   messageId: "0:m3",
                   title: "Console",
                   body: "Hello",
                   data: %{},
                   presentation: "foreground"
                 }
               ])

      assert data_only == %{
               presentation: :foreground,
               action: nil,
               source: :push,
               id: "0:m2",
               title: nil,
               body: nil,
               data: %{kind: "sync"}
             }

      assert %{title: "Console", body: "Hello", data: data, id: "0:m3"} = with_notification
      assert data == %{}
    end

    test "an unparseable mob_notification_json falls back to the message's own fields", ctx do
      assert [notification] =
               run(ctx, [
                 %{
                   fn: "fromMessage",
                   messageId: "0:m4",
                   title: "T",
                   body: "B",
                   data: %{"mob_notification_json" => "not json", "k" => "v"},
                   presentation: "foreground"
                 }
               ])

      assert %{title: "T", body: "B", data: %{k: "v"}, presentation: :foreground} = notification
    end
  end

  describe "the manifest components the plugin declares" do
    test "name classes the bridge actually ships", ctx do
      names =
        for snippet <- ctx.manifest.android.manifest_application_snippets,
            [_, name] <- [Regex.run(~r/android:name="([^"]+)"/, snippet)],
            do: name

      assert "io.mob.notify.MobFirebaseService" in names
      assert "io.mob.notify.MobNotifyBootReceiver" in names

      for name <- names do
        class_file = Path.join(ctx.out, String.replace(name, ".", "/") <> ".class")
        assert File.exists?(class_file), "#{name} is declared but not compiled from bridge_kt"
      end
    end
  end
end
