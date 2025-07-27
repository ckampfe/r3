defmodule R3Web.ReaderHTML do
  @moduledoc """
  This module contains pages rendered by ReaderController.

  See the `reader_html` directory for all templates available.
  """
  use R3Web, :html

  use Phoenix.VerifiedRoutes, endpoint: R3Web.Endpoint, router: R3Web.Router

  embed_templates "reader_html/*"

  def read_toggle(assigns) do
    ~H"""
    <a phx-no-format class="link p-2" href={~p"/feeds/#{@feed.id}?entries_visibility=#{@visibility}"}>View {@visibility}</a>
    """
  end

  def info_notification(assigns) do
    ~H"""
    <div
      role="alert"
      class="sticky alert alert-info absolute inset-0 z-50 my-4 fade-me-out"
      hx-trigger="load delay:5s"
      hx-swap="delete swap:2s"
      hx-delete={~p"/empty"}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        class="h-6 w-6 shrink-0 stroke-current"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        >
        </path>
      </svg>
      <span>{@message}</span>
    </div>
    """
  end

  def progress_bar(assigns) do
    ~H"""
    <div class="sticky top-0 z-50 w-full">
      <div class="relative overflow-hidden h-1.5 bg-transparent w-full">
        <div id="progress" class="h-full w-full bg-mypink" style="width: 0%"></div>
      </div>

      <script>
        function getScrollProgress() {
          const scrollTop = window.scrollY;
          const documentHeight = document.documentElement.scrollHeight;
          const viewportHeight = window.innerHeight;
          const totalScrollableHeight = documentHeight - viewportHeight;

          if (totalScrollableHeight === 0) {
              return 0; // Avoid division by zero if the page is not scrollable
          }

          const scrollProgress = (scrollTop / totalScrollableHeight) * 100;
          // round to nearest tenth
          return scrollProgress.toFixed(1);
        }

        window.addEventListener('scroll', () => {
          const progress = getScrollProgress();
          const progressEl = document.getElementById("progress");
          progressEl.style.width = `${progress.toString()}%`;
        });
      </script>
    </div>
    """
  end
end
