defmodule Mosaic.PayrollTest do
  use Mosaic.DataCase

  alias Mosaic.Payroll
  alias Mosaic.Timekeeping
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "create_payroll_piece/2" do
    test "creates payroll piece with valid attributes" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 13:00:00Z],
        "properties" => %{
          "cost_center" => "WAREHOUSE",
          "job_code" => "RECEIVING",
          "rate_type" => "regular"
        }
      }

      assert {:ok, payroll_piece} = Payroll.create_payroll_piece(clock_period.id, attrs)
      assert payroll_piece.start_time == ~U[2024-01-15 09:00:00Z]
      assert payroll_piece.end_time == ~U[2024-01-15 13:00:00Z]
      assert payroll_piece.parent_id == clock_period.id
      assert payroll_piece.properties["cost_center"] == "WAREHOUSE"
      assert payroll_piece.properties["job_code"] == "RECEIVING"
      assert payroll_piece.properties["rate_type"] == "regular"
      assert payroll_piece.status == "active"
    end

    test "creates payroll piece with overtime rate_type" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 19:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Regular time 9am-5pm (8 hours)
      regular_attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z],
        "properties" => %{
          "rate_type" => "regular"
        }
      }

      # Overtime 5pm-7pm (2 hours)
      overtime_attrs = %{
        "start_time" => ~U[2024-01-15 17:00:00Z],
        "end_time" => ~U[2024-01-15 19:00:00Z],
        "properties" => %{
          "rate_type" => "overtime"
        }
      }

      assert {:ok, regular_piece} = Payroll.create_payroll_piece(clock_period.id, regular_attrs)
      assert {:ok, overtime_piece} = Payroll.create_payroll_piece(clock_period.id, overtime_attrs)

      assert regular_piece.properties["rate_type"] == "regular"
      assert overtime_piece.properties["rate_type"] == "overtime"
    end

    test "creates payroll piece with union_rule" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z],
        "properties" => %{
          "union_rule" => "TEAMSTERS_LOCAL_123",
          "rate_type" => "regular"
        }
      }

      assert {:ok, payroll_piece} = Payroll.create_payroll_piece(clock_period.id, attrs)
      assert payroll_piece.properties["union_rule"] == "TEAMSTERS_LOCAL_123"
    end

    test "validates payroll piece is within clock period boundaries" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Payroll piece starts before clock period
      attrs = %{
        "start_time" => ~U[2024-01-15 08:00:00Z],
        "end_time" => ~U[2024-01-15 13:00:00Z]
      }

      assert {:error, reason} = Payroll.create_payroll_piece(clock_period.id, attrs)
      assert reason =~ "Payroll piece starts before clock period"
    end

    test "validates payroll piece does not end after clock period" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Payroll piece ends after clock period
      attrs = %{
        "start_time" => ~U[2024-01-15 13:00:00Z],
        "end_time" => ~U[2024-01-15 18:00:00Z]
      }

      assert {:error, reason} = Payroll.create_payroll_piece(clock_period.id, attrs)
      assert reason =~ "Payroll piece ends after clock period"
    end

    test "requires start_time and end_time" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      attrs = %{"start_time" => ~U[2024-01-15 09:00:00Z]}

      assert {:error, reason} = Payroll.create_payroll_piece(clock_period.id, attrs)
      assert reason =~ "End time is required"
    end

    test "allows multiple payroll pieces per clock period" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Morning: different cost center
      morning_attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 13:00:00Z],
        "properties" => %{
          "cost_center" => "WAREHOUSE",
          "rate_type" => "regular"
        }
      }

      # Afternoon: different cost center
      afternoon_attrs = %{
        "start_time" => ~U[2024-01-15 13:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z],
        "properties" => %{
          "cost_center" => "SHIPPING",
          "rate_type" => "regular"
        }
      }

      assert {:ok, piece1} = Payroll.create_payroll_piece(clock_period.id, morning_attrs)
      assert {:ok, piece2} = Payroll.create_payroll_piece(clock_period.id, afternoon_attrs)

      assert piece1.properties["cost_center"] == "WAREHOUSE"
      assert piece2.properties["cost_center"] == "SHIPPING"
      assert piece1.id != piece2.id
    end

    test "validates clock period exists" do
      fake_id = Ecto.UUID.generate()

      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      assert {:error, reason} = Payroll.create_payroll_piece(fake_id, attrs)
      assert reason =~ "Event not found"
    end
  end

  describe "list_payroll_pieces/1" do
    test "returns all payroll pieces for clock period" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      piece1_attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 13:00:00Z],
        "properties" => %{"cost_center" => "A"}
      }

      piece2_attrs = %{
        "start_time" => ~U[2024-01-15 13:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z],
        "properties" => %{"cost_center" => "B"}
      }

      {:ok, piece1} = Payroll.create_payroll_piece(clock_period.id, piece1_attrs)
      {:ok, piece2} = Payroll.create_payroll_piece(clock_period.id, piece2_attrs)

      pieces = Payroll.list_payroll_pieces(clock_period.id)
      piece_ids = Enum.map(pieces, & &1.id)

      assert length(pieces) == 2
      assert piece1.id in piece_ids
      assert piece2.id in piece_ids
    end

    test "returns payroll pieces ordered by start_time" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Create in reverse order
      piece2_attrs = %{
        "start_time" => ~U[2024-01-15 13:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      piece1_attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 13:00:00Z]
      }

      {:ok, _piece2} = Payroll.create_payroll_piece(clock_period.id, piece2_attrs)
      {:ok, piece1} = Payroll.create_payroll_piece(clock_period.id, piece1_attrs)

      pieces = Payroll.list_payroll_pieces(clock_period.id)

      # Should be ordered by start_time ascending
      assert List.first(pieces).id == piece1.id
      assert List.first(pieces).start_time == ~U[2024-01-15 09:00:00Z]
    end

    test "returns empty list for clock period with no payroll pieces" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      assert Payroll.list_payroll_pieces(clock_period.id) == []
    end

    test "does not return payroll pieces from other clock periods" do
      worker = worker_fixture()

      # First clock period
      {:ok, clock_in1} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out1} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, period1} = Timekeeping.create_clock_period(worker.id, clock_in1.id, clock_out1.id)

      # Second clock period
      {:ok, clock_in2} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-16 09:00:00Z])
      {:ok, clock_out2} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-16 17:00:00Z])

      {:ok, period2} = Timekeeping.create_clock_period(worker.id, clock_in2.id, clock_out2.id)

      # Create piece in period 1
      piece1_attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      {:ok, piece1} = Payroll.create_payroll_piece(period1.id, piece1_attrs)

      # Create piece in period 2
      piece2_attrs = %{
        "start_time" => ~U[2024-01-16 09:00:00Z],
        "end_time" => ~U[2024-01-16 17:00:00Z]
      }

      {:ok, _piece2} = Payroll.create_payroll_piece(period2.id, piece2_attrs)

      # List pieces for period 1 should only return piece1
      pieces = Payroll.list_payroll_pieces(period1.id)
      piece_ids = Enum.map(pieces, & &1.id)

      assert length(pieces) == 1
      assert piece1.id in piece_ids
    end
  end

  describe "calculate_hours_by_rate_type/1" do
    test "calculates total hours for each rate type" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 19:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # Regular: 8 hours
      {:ok, _regular} =
        Payroll.create_payroll_piece(clock_period.id, %{
          "start_time" => ~U[2024-01-15 09:00:00Z],
          "end_time" => ~U[2024-01-15 17:00:00Z],
          "properties" => %{"rate_type" => "regular"}
        })

      # Overtime: 2 hours
      {:ok, _overtime} =
        Payroll.create_payroll_piece(clock_period.id, %{
          "start_time" => ~U[2024-01-15 17:00:00Z],
          "end_time" => ~U[2024-01-15 19:00:00Z],
          "properties" => %{"rate_type" => "overtime"}
        })

      hours_by_type = Payroll.calculate_hours_by_rate_type(clock_period.id)

      assert hours_by_type["regular"] == 8.0
      assert hours_by_type["overtime"] == 2.0
    end

    test "defaults to 'regular' rate type if not specified" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      # No rate_type specified
      {:ok, _piece} =
        Payroll.create_payroll_piece(clock_period.id, %{
          "start_time" => ~U[2024-01-15 09:00:00Z],
          "end_time" => ~U[2024-01-15 17:00:00Z],
          "properties" => %{}
        })

      hours_by_type = Payroll.calculate_hours_by_rate_type(clock_period.id)

      assert hours_by_type["regular"] == 8.0
    end

    test "returns empty map for clock period with no payroll pieces" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, clock_period} =
        Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      hours_by_type = Payroll.calculate_hours_by_rate_type(clock_period.id)

      assert hours_by_type == %{}
    end
  end
end
