# frozen_string_literal: true

require "test_helper"

class TestDrecs < Minitest::Test
  include Drecs

  system :test, :component_a do
    123
  end

  def test_that_it_has_a_version_number
    refute_nil ::Drecs::VERSION
  end

  def test_systems_are_registered
    assert true, Drecs::SYSTEMS.include?(:test)
  end
end
