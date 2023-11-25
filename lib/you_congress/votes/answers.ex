defmodule YouCongress.Votes.Answers do
  @moduledoc """
  The Answers context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Repo
  alias YouCongress.Votes.Answers.Answer

  @basic_responses %{
    1 => "Strongly agree",
    2 => "Agree",
    3 => "Abstain",
    4 => "N/A",
    5 => "Disagree",
    6 => "Strongly disagree"
  }

  @basic_answers %{
    "Strongly agree" => 1,
    "Agree" => 2,
    "Abstain" => 3,
    "N/A" => 4,
    "Disagree" => 5,
    "Strongly disagree" => 6
  }

  def basic_answers, do: @basic_answers

  def basic_responses, do: @basic_responses

  @doc """
  Returns the list of answers.

  ## Examples

      iex> list_answers()
      [%Answer{}, ...]

  """
  def list_answers do
    Repo.all(Answer)
  end

  @doc """
  Gets a single answer.

  Raises `Ecto.NoResultsError` if the Answer does not exist.

  ## Examples

      iex> get_answer!(123)
      %Answer{}

      iex> get_answer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_answer!(id), do: Repo.get!(Answer, id)

  @doc """
  Gets a single answer by response.

  ## Examples

      iex> get_answer_by_response("Strongly Agree")
      %Answer{}

      iex> get_answer_by_response("Bad Value")
      nil
  """
  def get_answer_by_response(response) do
    Repo.get_by(Answer, response: response)
  end

  @doc """
  Returns a random answer.

  ## Examples

      iex> get_random_answer()
      %Answer{}

  """
  def get_random_answer do
    Repo.one(from(a in Answer, order_by: [asc: fragment("RANDOM()")], limit: 1))
  end

  def get_basic_answer_id(response) do
    @basic_answers[response]
  end

  @doc """
  Creates an answer.

  ## Examples

      iex> create_answer(%{response: "Strongly Agree"})
      {:ok, %Answer{}}

      iex> create_answer(%{response: "Bad Value"})
      {:error, %Ecto.Changeset{}}

  """
  def create_answer(attrs \\ %{}) do
    %Answer{}
    |> Answer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an answer.

  ## Examples

      iex> update_answer(answer, %{response: "Strongly Disagree"})
      {:ok, %Answer{}}

      iex> update_answer(answer, %{response: "Bad Value"})
      {:error, %Ecto.Changeset{}}

  """
  def update_answer(%Answer{} = answer, attrs) do
    answer
    |> Answer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an answer.

  ## Examples

      iex> delete_answer(answer)
      {:ok, %Answer{}}

      iex> delete_answer(answer)
      {:error, %Ecto.Changeset{}}

  """
  def delete_answer(%Answer{} = answer) do
    Repo.delete(answer)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking answer changes.

  ## Examples

      iex> change_answer(answer)
      %Ecto.Changeset{data: %Answer{}}

  """
  def change_answer(%Answer{} = answer, attrs \\ %{}) do
    Answer.changeset(answer, attrs)
  end
end
