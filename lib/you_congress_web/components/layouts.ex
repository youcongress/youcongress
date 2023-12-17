defmodule YouCongressWeb.Layouts do
  @moduledoc """
  Define project layouts
  """
  use YouCongressWeb, :html

  import YouCongressWeb.TopHeaderComponent
  import YouCongressWeb.Components.FooterComponent

  embed_templates "layouts/*"
end
