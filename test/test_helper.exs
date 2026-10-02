defmodule MobNotify.KotlinHost do
  @moduledoc false
  # What test/mob_fcm_envelope_test.exs needs to compile MobNotifyBridge.kt and
  # run it on the host JVM: kotlinc + kotlin, an Android SDK platform's
  # android.jar (compile classpath), and an org.json jar (runtime: android.jar's
  # org.json is stubs that throw). MOB_NOTIFY_ORG_JSON_JAR overrides the jar
  # Gradle caches for any Android build.

  def toolchain do
    with {:ok, kotlinc} <- executable("kotlinc"),
         {:ok, kotlin} <- executable("kotlin"),
         {:ok, android_jar} <- android_jar(),
         {:ok, json_jar} <- org_json_jar() do
      {:ok, %{kotlinc: kotlinc, kotlin: kotlin, android_jar: android_jar, json_jar: json_jar}}
    end
  end

  defp executable(name) do
    case System.find_executable(name) do
      nil -> {:error, "#{name} not on PATH"}
      path -> {:ok, path}
    end
  end

  defp android_jar do
    sdk =
      System.get_env("ANDROID_HOME") || System.get_env("ANDROID_SDK_ROOT") ||
        Path.expand("~/Library/Android/sdk")

    sdk
    |> Path.join("platforms/android-*/android.jar")
    |> Path.wildcard()
    |> Enum.max_by(&platform_level/1, fn -> nil end)
    |> case do
      nil -> {:error, "no android.jar under #{sdk}/platforms"}
      jar -> {:ok, jar}
    end
  end

  defp platform_level(jar) do
    case Regex.run(~r/android-(\d+)/, jar) do
      [_, level] -> String.to_integer(level)
      _ -> 0
    end
  end

  defp org_json_jar do
    case System.get_env("MOB_NOTIFY_ORG_JSON_JAR") do
      nil ->
        "~/.gradle/caches/modules-2/files-2.1/org.json/json/*/*/json-*.jar"
        |> Path.expand()
        |> Path.wildcard()
        |> Enum.reject(&String.ends_with?(&1, "-sources.jar"))
        |> Enum.sort()
        |> List.last()
        |> case do
          nil -> {:error, "no org.json jar (set MOB_NOTIFY_ORG_JSON_JAR)"}
          jar -> {:ok, jar}
        end

      jar ->
        {:ok, jar}
    end
  end
end

case MobNotify.KotlinHost.toolchain() do
  {:ok, _} ->
    ExUnit.start()

  {:error, reason} ->
    IO.puts("Excluding :kotlin_host tests: #{reason}")
    ExUnit.start(exclude: [:kotlin_host])
end
