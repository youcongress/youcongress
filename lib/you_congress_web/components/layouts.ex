defmodule YouCongressWeb.Layouts do
  @moduledoc """
  Define project layouts
  """
  use YouCongressWeb, :html

  import YouCongressWeb.TopHeaderComponent

  embed_templates "layouts/*"
end
