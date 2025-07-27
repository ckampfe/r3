defmodule R3Web.ReaderHTML do
  @moduledoc """
  This module contains pages rendered by ReaderController.

  See the `reader_html` directory for all templates available.
  """
  use R3Web, :html

  use Phoenix.VerifiedRoutes, endpoint: R3Web.Endpoint, router: R3Web.Router

  embed_templates "reader_html/*"

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
