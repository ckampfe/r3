defmodule R3Web.ReaderController do
  use R3Web, :controller

  require Logger

  alias R3.Reader
  alias R3.Reader.{Entry, Feed}
  alias R3.Repo
  import Ecto.Query
  import Ecto.Changeset

  def index(conn, _params) do
    feeds =
      Feed
      |> join(:inner, [f], e in Entry, on: e.feed_id == f.id)
      |> select([f, e], %{
        id: f.id,
        title: f.title,
        refreshed_at: f.refreshed_at,
        unread_entries: sum(fragment("case when ? is null then 1 else 0 end", e.read_at)),
        read_entries: sum(fragment("case when ? is not null then 1 else 0 end", e.read_at)),
        most_recent_entry: max(fragment("coalesce(?, ?)", e.pub_date, e.inserted_at))
      })
      |> group_by([f], f.id)
      |> order_by([f], fragment("lower(?)", f.title))
      |> Repo.all()

    render(conn, :index, page_title: "Feeds", feeds: feeds)
  end

  def feed_create(conn, _params) do
    with [maybe_url] <- Plug.Conn.get_req_header(conn, "hx-prompt"),
         {:ok, parsed_uri} <- URI.new(maybe_url),
         feed_link = URI.to_string(parsed_uri),
         nil <- Reader.feed_exists?(feed_link),
         {:ok, feed_response} <- Req.get(feed_link),
         {:ok, feed_kind, parsed_feed} <- Reader.try_to_parse_feed(feed_response.body),
         {:ok, _} <- Reader.add_feed(parsed_feed, feed_kind, feed_link) do
      conn
      |> put_resp_header("HX-Location", "/")
      |> send_resp(201, "")
    else
      {:error, e} ->
        conn
        |> put_resp_header(
          "HX-Trigger",
          JSON.encode!(%{"feedCreateError" => e})
        )
        |> send_resp(:bad_request, "")
    end
  end

  def feed_show(conn, params) do
    default = %{entries_visibility: "unread"}

    cs =
      {default, %{feed_id: :integer, entries_visibility: :string}}
      |> cast(params, [:feed_id, :entries_visibility])
      |> validate_required([:feed_id, :entries_visibility])
      |> validate_inclusion(:entries_visibility, ["read", "unread", "all"])

    cs =
      if cs.valid? do
        Ecto.Changeset.apply_changes(cs)
      else
        raise cs.errors
      end

    entries =
      Entry
      |> where([e], e.feed_id == ^cs.feed_id)
      |> select([:id, :title, :pub_date, :link, :read_at])
      |> order_by([e], desc: e.pub_date)

    entries =
      case cs.entries_visibility do
        "read" ->
          entries |> where([e], not is_nil(e.read_at))

        "unread" ->
          entries |> where([e], is_nil(e.read_at))

        "all" ->
          entries
      end

    entries = Repo.all(entries)

    feed =
      Feed
      |> where([f], f.id == ^cs.feed_id)
      |> select([:id, :title])
      |> Repo.one()

    render(conn, :feed_show,
      page_title: feed.title,
      entries_visibility: cs.entries_visibility,
      feed: feed,
      entries: entries
    )
  end

  #  get feed entries
  #  TODO v2: if cache miss
  #  get links for challenger entries
  #  get links for existing entries
  #  set = remote_entries - existing_entries
  #  in transaction:
  #  - for entry in set: insert
  #  - update feed refreshed_at
  #  - TODO v2: update_feed_etag
  def feed_refresh(conn, %{"feed_id" => feed_id}) do
    {:ok, _new_entries_count} = Reader.refresh_feed(feed_id)

    # forcing a reload is stupid but works
    conn
    |> put_resp_header("HX-Refresh", "true")
    |> send_resp(200, "")
  end

  def feeds_refresh(conn, _params) do
    feed_ids =
      Feed
      |> select([:id])
      |> Repo.all()
      |> Enum.map(fn feed -> feed.id end)

    %{successes: successes, errors: errors} =
      Task.Supervisor.async_stream_nolink(R3.TaskSupervisor, feed_ids, Reader, :refresh_feed, [],
        ordered: false,
        on_timeout: :kill_task,
        zip_input_on_exit: true,
        timeout: :timer.seconds(5)
      )
      |> Enum.reduce(%{successes: 0, errors: []}, fn
        {:ok, _}, acc ->
          Map.update!(acc, :successes, fn i -> i + 1 end)

        {:exit, {_feed_id, _reason} = e}, acc ->
          Map.update!(acc, :errors, fn errors ->
            [e | errors]
          end)
      end)

    # TODO what to do with these titles and errors
    if !Enum.empty?(errors) do
      error_map = Enum.into(errors, %{})
      error_feed_ids = Map.keys(error_map)

      error_titles =
        Feed
        |> where([f], f.id in ^error_feed_ids)
        |> select([:id, :title])
        |> Repo.all()
        |> Enum.map(fn feed -> {feed.id, feed.title} end)
        |> Enum.into(%{})

      title_and_errors =
        Map.merge(error_titles, error_map, fn _id, feed_title, error_reason ->
          %{title: feed_title, error: error_reason}
        end)

      Enum.each(title_and_errors, fn {_id, %{title: title, error: error}} ->
        Logger.error("#{title}: #{inspect(error)}")
      end)
    end

    # this is no longer a named template in the reader_html directory,
    # like, info_notification.html.heex.
    #
    # it is a function component defined in read_html.ex
    conn
    |> put_root_layout(false)
    |> render(:info_notification,
      message: "#{successes} feeds refreshed successfully. #{Enum.count(errors)} errors."
    )
  end

  def entry_show(conn, %{"entry_id" => entry_id}) do
    {entry_id, _} = Integer.parse(entry_id)

    entry =
      Entry
      |> where([e], e.id == ^entry_id)
      |> select([
        :id,
        :feed_id,
        :title,
        :author,
        :description,
        :content,
        :pub_date,
        :link,
        :read_at,
        :inserted_at
      ])
      |> Repo.one!()

    feed =
      Feed
      |> where([f], f.id == ^entry.feed_id)
      |> select([:title])
      |> Repo.one!()

    content =
      cond do
        entry.content && entry.description ->
          if String.length(entry.content) >= String.length(entry.description) do
            entry.content
          else
            entry.description
          end

        entry.content ->
          entry.content

        true ->
          entry.description
      end

    cleaned = HtmlSanitizeEx.markdown_html(content)

    render(conn, :entry_show,
      page_title: entry.title,
      entry: entry,
      feed: feed,
      cleaned: cleaned
    )
  end

  def entry_toggle_read_at(conn, %{"entry_id" => entry_id}) do
    {entry_id, _} = Integer.parse(entry_id)

    {:ok, read_at} = Reader.toggle_read_at(entry_id)

    conn
    |> put_root_layout(false)
    |> send_resp(200, if(read_at, do: "Mark unread", else: "Mark read"))
  end

  def empty(conn, _params) do
    send_resp(conn, 200, "")
  end
end
