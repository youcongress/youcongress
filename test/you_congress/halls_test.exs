defmodule YouCongress.HallsTest do
  use YouCongress.DataCase

  alias YouCongress.Halls

  describe "halls" do
    alias YouCongress.Halls.Hall

    import YouCongress.HallsFixtures

    @invalid_attrs %{name: nil}

    test "list_halls/0 returns all halls" do
      hall = hall_fixture()
      assert Halls.list_halls() == [hall]
    end

    test "get_hall!/1 returns the hall with given id" do
      hall = hall_fixture()
      assert Halls.get_hall!(hall.id) == hall
    end

    test "create_hall/1 with valid data creates a hall" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Hall{} = hall} = Halls.create_hall(valid_attrs)
      assert hall.name == "some name"
    end

    test "create_hall/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Halls.create_hall(@invalid_attrs)
    end

    test "update_hall/2 with valid data updates the hall" do
      hall = hall_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Hall{} = hall} = Halls.update_hall(hall, update_attrs)
      assert hall.name == "some updated name"
    end

    test "update_hall/2 with invalid data returns error changeset" do
      hall = hall_fixture()
      assert {:error, %Ecto.Changeset{}} = Halls.update_hall(hall, @invalid_attrs)
      assert hall == Halls.get_hall!(hall.id)
    end

    test "delete_hall/1 deletes the hall" do
      hall = hall_fixture()
      assert {:ok, %Hall{}} = Halls.delete_hall(hall)
      assert_raise Ecto.NoResultsError, fn -> Halls.get_hall!(hall.id) end
    end

    test "change_hall/1 returns a hall changeset" do
      hall = hall_fixture()
      assert %Ecto.Changeset{} = Halls.change_hall(hall)
    end
  end
end
