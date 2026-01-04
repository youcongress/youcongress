defmodule YouCongress.SearchParserTest do
  use ExUnit.Case, async: true
  alias YouCongress.SearchParser

  describe "parse/1" do
    test "parses simple space-separated terms" do
      assert SearchParser.parse("hello world") == ["hello", "world"]
    end

    test "parses quoted terms as single units" do
      assert SearchParser.parse("hello \"new world\"") == ["hello", "new world"]
    end

    test "parses only quoted term" do
      assert SearchParser.parse("\"state of the art\"") == ["state of the art"]
    end

    test "handles multiple quoted terms" do
      assert SearchParser.parse(~s("foo bar" "baz qux")) == ["foo bar", "baz qux"]
    end

    test "ignores empty strings and nil" do
      assert SearchParser.parse(nil) == []
      assert SearchParser.parse("") == []
    end

    test "handles mixed terms" do
      assert SearchParser.parse("term1 \"term 2\" term3") == ["term1", "term 2", "term3"]
    end

    test "closes unclosed quotes" do
      assert SearchParser.parse("\"artificial intelligence") == ["artificial intelligence"]
      assert SearchParser.parse("foo \"bar") == ["foo", "bar"]
    end
  end
end
