Mix.install([:jason, :finch, :nimble_csv])

defmodule Height do
  alias NimbleCSV.RFC4180, as: CSV
  require Logger

  @status_order ["To do", "Doing", "QA Engenharia", "Done"]

  def run do
    Finch.start_link(name: Height)
    :telemetry.attach(__MODULE__, [:finch, :request, :stop], &__MODULE__.handle_event/4, nil)

    status_map = get_status_map()
    stories_list = get_stories_list()

    stories_list
    |> Map.fetch!("id")
    |> get_tasks(status_map)
    |> map("Getting activities", fn task ->
      activities =
        task.id
        |> get_activities(status_map)
        |> Enum.reject(&status_surpassed?(&1.status, task.status))

      Map.put(task, :activities, activities)
    end)
    |> tap(&write_to_json/1)
    |> tap(&write_to_csv/1)
  end

  defp write_to_json(result) do
    file_name = "height-stories-#{Date.utc_today()}.json"
    file_path = Path.join(File.cwd!(), file_name)

    result
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(file_path, &1))

    Logger.info("Results written to #{file_path}")
  end

  defp write_to_csv(result) do
    file_name = "height-stories-#{Date.utc_today()}.csv"
    file_path = Path.join(File.cwd!(), file_name)

    result
    |> Enum.map(fn task ->
      [
        task.index,
        task.name,
        get_date_of_status_change(task, 0),
        get_date_of_status_change(task, 1),
        get_date_of_status_change(task, 2),
        get_date_of_status_change(task, 3)
      ]
    end)
    |> prepend(["#id", "item name", "TODO", "DOING", "QA", "DONE"])
    |> CSV.dump_to_iodata()
    |> then(&File.write!(file_path, &1))

    Logger.info("Results written to #{file_path}")
  end

  defp get_date_of_status_change(task, column_index) do
    status = Enum.at(@status_order, column_index)

    case Enum.find(task.activities, fn a -> a.status == status end) do
      nil -> nil
      %{} = activity -> Calendar.strftime(activity.created_at, "%d/%m/%y")
    end
  end

  defp prepend(list, item) do
    [item | list]
  end

  defp map(list, action, fun) do
    total = Enum.count(list)

    list
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      Logger.info("#{action} - #{index} of #{total}")
      fun.(item)
    end)
  end

  defp get_status_map do
    "/fieldTemplates"
    |> get()
    |> Map.fetch!("list")
    |> Enum.filter(fn template -> template["name"] == "Status" end)
    |> Enum.flat_map(fn template -> template["labels"] end)
    |> Map.new(fn template -> {template["id"], template["value"]} end)
  end

  defp get_tasks(list_id, status_map) do
    filters = %{
      "listIds" => %{"values" => [list_id]}
    }

    "/tasks"
    |> get(%{"filters" => Jason.encode!(filters)})
    |> Map.fetch!("list")
    |> Enum.reject(& &1["deleted"])
    |> Enum.map(fn task ->
      {:ok, datetime, _tz} = DateTime.from_iso8601(task["createdAt"])

      %{
        id: task["id"],
        created_at: DateTime.to_date(datetime),
        status: Map.fetch!(status_map, task["status"]),
        name: task["name"],
        index: task["index"]
      }
    end)
    |> Enum.filter(&supported_status?(&1.status))
    |> Enum.sort_by(& &1.created_at, Date)
  end

  defp get_activities(task_id, status_map) do
    "/activities"
    |> get(%{"taskId" => task_id})
    |> Map.fetch!("list")
    |> Enum.filter(fn activity -> activity["type"] == "statusChange" end)
    |> Enum.map(fn activity ->
      {:ok, datetime, _tz} = DateTime.from_iso8601(activity["createdAt"])

      %{
        status: Map.fetch!(status_map, activity["newValue"]),
        created_at: DateTime.to_date(datetime)
      }
    end)
    |> Enum.sort_by(& &1.created_at, Date)
    |> Enum.uniq_by(fn activity -> activity.status end)
    |> Enum.filter(&supported_status?(&1.status))
  end

  defp get_stories_list do
    "/lists"
    |> get()
    |> Map.fetch!("list")
    |> Enum.find(fn item -> item["key"] == "stories" end)
  end

  defp supported_status?(status) do
    Enum.member?(@status_order, status)
  end

  defp status_surpassed?(activity_status, task_status) do
    Enum.find_index(@status_order, fn status -> status == activity_status end) >
      Enum.find_index(@status_order, fn status -> status == task_status end)
  end

  defp get(path, query \\ %{}) do
    url =
      "https://api.height.app"
      |> URI.new!()
      |> Map.put(:path, path)
      |> Map.put(:query, URI.encode_query(query))
      |> URI.to_string()

    api_secret = System.fetch_env!("HEIGHT_SECRET_KEY")

    with_cache(:get, url, fn ->
      with_retry(fn ->
        :get
        |> Finch.build(url, [
          {"Authorization", "api-key #{api_secret}"}
        ])
        |> Finch.request(Height)
      end)
    end)
  end

  defp with_retry(request_fun, attempt \\ 1) do
    case request_fun.() do
      {:ok, %{status: 200, body: body}} ->
        Jason.decode!(body)

      result ->
        if attempt >= 10 do
          raise "max attempts exceeded"
        else
          time_to_sleep =
            case result do
              {:ok, %{status: 429, headers: headers}} ->
                value = :proplists.get_value("retry-after", headers)

                String.to_integer(value) * 1000

              _other ->
                attempt * 5000
            end

          new_attempt = attempt + 1

          Logger.info("Sleeping for #{time_to_sleep}ms")
          Process.sleep(time_to_sleep)

          Logger.info("Retrying, attempt #{new_attempt}")

          with_retry(request_fun, new_attempt)
        end
    end
  end

  defp with_cache(method, url, fun) do
    file_name =
      "#{Date.utc_today()}-#{method}-#{Base.encode32(url, padding: false, case: :lower)}.json"

    base_path = Path.join(System.tmp_dir!(), "height-api-cache")
    file_path = Path.join(base_path, file_name)

    File.mkdir_p!(base_path)

    if File.exists?(file_path) do
      Logger.info("Reading from cache #{method} #{url} at #{file_path}")

      file_path |> File.read!() |> Jason.decode!()
    else
      result = fun.()

      Logger.info("Writing result to cache at #{file_path}")
      File.write!(file_path, Jason.encode!(result))

      result
    end
  end

  def handle_event(
        [:finch, :request, :stop],
        %{duration: duration},
        %{request: request, result: result},
        nil
      ) do
    url =
      ""
      |> URI.new!()
      |> Map.put(:scheme, to_string(request.scheme))
      |> Map.put(:host, request.host)
      |> Map.put(:path, request.path)
      |> Map.put(:query, request.query)
      |> Map.put(:port, request.port)
      |> URI.to_string()

    status =
      case result do
        {:ok, response} -> response.status
        {:error, _reason} -> :error
      end

    Logger.info("#{request.method} #{url} -> #{status} #{format_duration(duration)}")
  end

  defp format_duration(duration) do
    duration = System.convert_time_unit(duration, :native, :microsecond)

    if duration > 1000 do
      value = duration |> div(1000) |> Integer.to_string()
      value <> "ms"
    else
      Integer.to_string(duration) <> "µs"
    end
  end
end

Height.run()
