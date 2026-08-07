defmodule YouCongressWeb.AiPolicyLive do
  use YouCongressWeb, :live_view

  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Countries
  alias YouCongressWeb.ReturnTo

  # Where Google sends users back to: the "Join us" section, with a marker so we
  # can confirm the login happened.
  @google_return_to "/ai?from=google#register"

  defmodule Signup do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name, :string
      field :email, :string
      field :password, :string
      field :country_id, :integer
      field :professional_background, :string
      field :linkedin_or_website, :string
      field :interests, {:array, :string}, default: []
      field :availability_and_motivation, :string
    end

    def changeset(signup, attrs \\ %{}, require_account? \\ true) do
      signup
      |> cast(attrs, [
        :name,
        :email,
        :password,
        :country_id,
        :professional_background,
        :linkedin_or_website,
        :interests,
        :availability_and_motivation
      ])
      |> validate_required([:country_id])
      |> maybe_require_account(require_account?)
    end

    defp maybe_require_account(changeset, true) do
      changeset
      |> validate_required([:name, :email, :password])
      |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
      |> validate_length(:password, min: 8, max: 72)
    end

    defp maybe_require_account(changeset, false), do: changeset
  end

  @backgrounds [
    {"Technology / research", "tech"},
    {"Business / entrepreneurship", "business"},
    {"Employee, freelancer, or job seeker", "worker"},
    {"Education", "education"},
    {"Policy, law, or economics", "policy"},
    {"Civil society or trade union", "civil"},
    {"Journalism", "journalism"},
    {"Citizen", "citizen"},
    {"Other", "other"}
  ]

  @interests [
    {"Jobs & shared prosperity", "jobs"},
    {"Governance & safety", "governance"},
    {"Competitiveness & sovereignty", "competitiveness"}
  ]

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    user = socket.assigns.current_user
    context = (user && user.sign_up_context) || %{}

    values = %{
      "country_id" => user && user.author && user.author.country_id,
      "professional_background" => context["professional_background"],
      "linkedin_or_website" => context["linkedin_or_website"],
      "interests" => context["interests"] || [],
      "availability_and_motivation" => context["availability_and_motivation"]
    }

    {:ok,
     socket
     |> assign(:page_title, "AI Policy Group | YouCongress")
     |> assign(
       :page_description,
       "Join a global community building practical AI policy proposals."
     )
     |> assign(:current_user, user)
     |> assign(:countries, Countries.country_options())
     |> assign(:backgrounds, @backgrounds)
     |> assign(:interests, @interests)
     |> assign(:saved, false)
     |> assign(:google_href, ReturnTo.auth_path(:google, nil, @google_return_to))
     |> assign(:log_in_href, ReturnTo.log_in_path(nil, "/ai#register"))
     |> maybe_put_google_flash(params)
     |> assign_form(Signup.changeset(%Signup{}, values, is_nil(user)))}
  end

  defp maybe_put_google_flash(%{assigns: %{current_user: %{}}} = socket, %{"from" => "google"}) do
    put_flash(socket, :info, "Logged in with Google. Now you can register your interest.")
  end

  defp maybe_put_google_flash(socket, _params), do: socket

  @impl true
  def handle_event("validate", %{"signup" => attrs}, socket) do
    changeset = Signup.changeset(%Signup{}, attrs, is_nil(socket.assigns.current_user))
    {:noreply, assign_form(socket, %{changeset | action: :validate})}
  end

  def handle_event(
        "register-interest",
        %{"signup" => attrs},
        %{assigns: %{current_user: nil}} = socket
      ) do
    changeset = Signup.changeset(%Signup{}, attrs, true)

    if changeset.valid? do
      user_attrs = Map.take(attrs, ["email", "password"])

      with {:ok, %{user: user}} <- Accounts.register_ai_policy_user(user_attrs, attrs) do
        Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

        {:noreply,
         socket
         |> assign(:saved, true)
         |> put_flash(:info, "Your account has been created. Check your email to confirm it.")}
      else
        {:error, :user, %Changeset{} = error_changeset, _} ->
          {:noreply, assign_form(socket, copy_account_errors(changeset, error_changeset))}

        {:error, _step, %Changeset{} = error_changeset, _} ->
          {:noreply, assign_form(socket, copy_account_errors(changeset, error_changeset))}
      end
    else
      {:noreply, assign_form(socket, %{changeset | action: :validate})}
    end
  end

  def handle_event("register-interest", %{"signup" => attrs}, socket) do
    changeset = Signup.changeset(%Signup{}, attrs, false)

    if changeset.valid? do
      case Accounts.register_ai_policy_interest(socket.assigns.current_user, attrs) do
        {:ok, %{user: user, author: author}} ->
          {:noreply,
           socket
           |> assign(:current_user, %{user | author: author})
           |> assign(:saved, true)
           |> put_flash(:info, "Your interest has been registered.")}

        {:error, _step, %Changeset{} = error_changeset, _} ->
          {:noreply, assign_form(socket, copy_account_errors(changeset, error_changeset))}
      end
    else
      {:noreply, assign_form(socket, %{changeset | action: :validate})}
    end
  end

  defp copy_account_errors(changeset, error_changeset) do
    Enum.reduce(error_changeset.errors, %{changeset | action: :validate}, fn {field,
                                                                              {message, opts}},
                                                                             acc ->
      Changeset.add_error(acc, field, message, opts)
    end)
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def focus_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-zinc-700 bg-zinc-800 p-7">
      <p class="font-extrabold text-[#f0a882]">{@number}</p>
      <h3 class="mt-3 text-xl font-bold">{@title}</h3>
      <p class="mt-3 leading-relaxed text-zinc-400">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :detail, :string, required: true

  def fact(assigns) do
    ~H"""
    <div class="rounded-xl border border-zinc-700 bg-zinc-800 p-4">
      <p class="font-bold">{@label}</p>
      <p class="mt-1 text-sm text-zinc-400">{@detail}</p>
    </div>
    """
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :signup))
end
