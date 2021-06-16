require "http/client/response"
require "json"

module Discord
  # This exception is raised in `REST#request` when a request fails in general,
  # without returning a special error response.
  class StatusException < Exception
    getter response : HTTP::Client::Response

    def initialize(@response : HTTP::Client::Response)
    end

    # The status code of the response that caused this exception, for example
    # 500 or 418.
    def status_code : Int32
      @response.status_code
    end

    # The status message of the response that caused this exception, for example
    # "Internal Server Error" or "I'm A Teapot".
    def status_message : String
      @response.status_message
    end

    def message
      "#{@response.status_code} #{@response.status_message}"
    end

    def to_s(io)
      io << @response.status_code << " " << @response.status_message
    end
  end

  # An API error response.
  struct APIError
    include JSON::Serializable

    property code : Int32
    property errors : Hash(String, JSON::Any)
    property message : String
  end

  # This exception is raised in `REST#request` when a request fails with an
  # API error response that has a code and a descriptive message.
  class CodeException < StatusException
    getter error : APIError

    def initialize(@response : HTTP::Client::Response, @error : APIError)
    end

    # The API error code that was returned by Discord, for example 20001 or
    # 50016.
    def error_code : Int32
      @error.code
    end

    # The API error message that was returned by Discord, for example "Bots
    # cannot use this endpoint" or "Provided too few or too many messages to
    # delete. Must provide at least 2 and fewer than 100 messages to delete.".
    def error_message : String
      @error.message
    end

    def error_errors : Hash(String, JSON::Any)
      @error.errors
    end

    def human_errors : String
      if @error.errors.size == 0
        ""
      else
        "\n" + @error.errors.map do |key, e|
          "Field '#{key}' reported following errors:\n#{next_down(e)}"
        end.join
      end
    end

    private def next_down(e, offset = 2) : String
      if !e["_errors"]?
        e.as_h.map do |key, n|
          "#{" "*offset}Inner #{(num = key.to_i?) ? "#{human_int(num + 1)} element" : "field '#{key}'"} reported following errors:\n#{next_down(n, offset + 2)}"
        end.join
      else
        e["_errors"].as_a.map do |err|
          "#{" "*offset}- #{err["code"]} - #{err["message"]}\n"
        end.join
      end
    end

    private def human_int(nr)
      case
      when (ld = nr % 10) == 1 && (tld = nr % 100) != 11
        return "#{nr}st"
      when ld == 2 && tld != 12
        return "#{nr}nd"
      when ld == 3 && tld != 13
        return "#{nr}rd"
      else
        return "#{nr}th"
      end
    end

    def message
      "#{@response.status_code} #{@response.status_message}: Code #{@error.code} - #{@error.message}"
    end

    def to_s(io)
      io << @response.status_code << " " << @response.status_message << ": Code " << @error.code << " - " << @error.message
    end
  end
end
