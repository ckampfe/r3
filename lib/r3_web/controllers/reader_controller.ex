defmodule R3Web.ReaderController do
  use R3Web, :controller

  require Logger

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
      |> order_by([f], f.title)
      |> Repo.all()

    render(conn, :index, feeds: feeds)
  end

  def feed_create(conn, _params) do
    with [maybe_url] <- Plug.Conn.get_req_header(conn, "hx-prompt"),
         {:ok, parsed_uri} <- URI.new(maybe_url),
         feed_link = URI.to_string(parsed_uri),
         nil <- Reader.feed_exists?(feed_link),
         {:ok, feed_response} <- Req.get(feed_link),
         {:ok, parsed_feed} <- FastRSS.parse_rss(feed_response.body),
         {:ok, _} <- Reader.add_feed(parsed_feed, feed_link) do
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
    feed =
      Feed
      |> where([f], f.id == ^feed_id)
      |> select([:id, :feed_link, :etag])
      |> Repo.one!()

    headers = [{"User-Agent", "r3/1.0"}]

    headers =
      if feed.etag do
        headers ++ [{"If-None-Match", feed.etag}]
      else
        headers
      end

    {:ok, feed_response} =
      Req.get(url: feed.feed_link, headers: headers)

    case feed_response.status do
      304 ->
        Logger.debug("got 304, feed is the same")

        conn
        |> put_root_layout(false)
        |> render(:feed_refresh, new_entries_count: 0)

      200 ->
        Logger.debug("got 200, feed has changed, calculating new entries")

        {:ok, challenger_feed} = FastRSS.parse_rss(feed_response.body)

        existing_entries_links =
          Entry
          |> where([e], e.feed_id == ^feed_id)
          |> select([e], e.link)
          |> Repo.all()
          |> MapSet.new()

        new_entries =
          challenger_feed
          |> Map.fetch!("items")
          |> Enum.reject(fn entry ->
            MapSet.member?(existing_entries_links, Map.fetch!(entry, "link"))
          end)

        Repo.transact(fn ->
          now = DateTime.utc_now()

          feed_query =
            Feed
            |> where([f], f.id == ^feed_id)
            |> update([f], set: [refreshed_at: ^now])

          feed_query =
            if etag = feed_response.headers["etag"] do
              [etag] = etag
              etag = String.replace(etag, "\"", "")
              update(feed_query, [f], set: [etag: ^etag])
            else
              feed_query
            end

          Repo.update_all(feed_query, [])

          new_entry = Ecto.build_assoc(feed, :entries)

          # again N+1, but find because of SQLite
          Enum.each(new_entries, fn entry ->
            entry =
              entry
              |> Map.update!("pub_date", fn
                nil ->
                  nil

                pub_date ->
                  DateTimeParser.parse_datetime!(pub_date)
              end)

            new_entry
            |> Entry.changeset(entry)
            |> Repo.insert!()
          end)

          {:ok, nil}
        end)

        conn
        |> put_root_layout(false)
        |> render(:feed_refresh, new_entries_count: Enum.count(new_entries))
    end
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
        :read_at
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
