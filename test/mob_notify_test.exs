defmodule MobNotifyTest do
  use ExUnit.Case, async: true

  alias MobDev.Plugin.{Manifest, Validator}

  @plugin_dir Path.expand("..", __DIR__)
  @contract Code.eval_file(Path.join(__DIR__, "fixtures/push_contract.exs")) |> elem(0)

  describe "plugin manifest" do
    setup do
      {:ok, manifest} = Manifest.load(@plugin_dir)
      %{manifest: manifest}
    end

    test "loads and validates clean (round-trips)", %{manifest: m} do
      assert {:ok, ^m} = Manifest.validate(m)
    end

    test "classifies as tier 1 (NIF plugin)", %{manifest: m} do
      assert Manifest.tier(m) == 1
    end

    test "passes the full pre-publish validator", %{manifest: m} do
      assert %{errors: []} = Validator.validate_plugin(m, @plugin_dir)
    end

    test "declares the cross-platform NIF pattern: one module, both platforms",
         %{manifest: m} do
      assert [ios, android] = m.nifs
      assert ios.module == :mob_notify_nif and ios.platform == :ios and ios.lang == :objc
      assert android.module == :mob_notify_nif and android.platform == :android
      assert android.lang == :zig
    end

    test "declares POST_NOTIFICATIONS + the FCM client dep", %{manifest: m} do
      assert "android.permission.POST_NOTIFICATIONS" in m.android.permissions
      assert Enum.any?(m.android.gradle_deps, &(&1 =~ "firebase-messaging"))
    end

    test "declares all three host requirements (FCM service, google-services, AppDelegate token)",
         %{manifest: m} do
      assert length(m.host_requirements) == 3
      assert Enum.any?(m.host_requirements, &(&1 =~ "MobFirebaseService"))
      assert Enum.any?(m.host_requirements, &(&1 =~ "google-services"))
      assert Enum.any?(m.host_requirements, &(&1 =~ "mob_send_push_token"))
    end
  end

  describe "NIF stub agreement" do
    test "the manifest NIF module is the shipped .erl stub and loads on the host" do
      assert Code.ensure_loaded?(:mob_notify_nif)
    end

    test "every NIF the public API calls is exported by the stub at the right arity" do
      exports = :mob_notify_nif.module_info(:exports)

      for fa <- [notify_schedule: 1, notify_cancel: 1, notify_register_push: 0] do
        assert fa in exports, "#{inspect(fa)} missing from mob_notify_nif exports"
      end
    end

    test "host (no native linked) falls back to nif_not_loaded, not a load crash" do
      assert_raise ErlangError, ~r/nif_not_loaded/, fn ->
        :mob_notify_nif.notify_register_push()
      end
    end
  end

  describe "schedule_opts/1 (parity with old Mob.Notify)" do
    test "builds the exact JSON shape core's nif_notify_schedule consumes" do
      opts = MobNotify.schedule_opts(id: "r1", title: "T", body: "B", delay_seconds: 60)

      assert %{"id" => "r1", "title" => "T", "body" => "B", "data" => %{}} = opts
      assert is_integer(opts["trigger_at"])
      assert opts["trigger_at"] > DateTime.to_unix(DateTime.utc_now())
    end

    test "at: takes precedence and data keys are stringified" do
      at = ~U[2030-01-01 00:00:00Z]
      opts = MobNotify.schedule_opts(id: "r", title: "t", body: "b", at: at, data: %{screen: "x"})

      assert opts["trigger_at"] == DateTime.to_unix(at)
      assert opts["data"] == %{"screen" => "x"}
    end

    test "missing required keys raise" do
      assert_raise KeyError, fn -> MobNotify.schedule_opts(title: "t", body: "b") end
    end
  end

  describe "push contract (vendored fixture, shared with mob_push)" do
    test "registration message shapes are what core's native side delivers" do
      assert [{:push_token, :ios, ios_tok}, {:push_token, :android, android_tok}] =
               @contract.push_token_messages

      assert is_binary(ios_tok) and is_binary(android_tok)
    end

    test "the Android push envelope decodes to the documented handle_info shape" do
      decoded = @contract.mob_notification_decoded

      assert {:notification, promised} = @contract.device_push_notification
      assert decoded["title"] == promised.title
      assert decoded["body"] == promised.body
      assert decoded["source"] == "push" and promised.source == :push
      assert decoded["data"] == promised.data
    end

    test "the known iOS source-drift is still open (delete this when Stage 1b/2 fixes it)" do
      # ios/mob_nif.m's delegate hardcodes source "local" + omits title/body;
      # the contract documents the Android envelope as the promise. When the
      # native pass aligns iOS, flip the fixture's :known_drift to :resolved
      # in BOTH repos and update device_local/push shapes accordingly.
      assert @contract.known_drift == :ios_delegate_hardcodes_local_source
    end
  end

  describe "public API surface (extraction parity with old Mob.Notify)" do
    test "exports the full extracted surface" do
      exports = MobNotify.__info__(:functions)

      for fa <- [schedule: 2, cancel: 2, register_push: 1, schedule_opts: 1] do
        assert fa in exports, "#{inspect(fa)} missing from MobNotify"
      end
    end
  end
end
