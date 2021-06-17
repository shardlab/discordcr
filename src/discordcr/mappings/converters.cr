module Discord
  # :nodoc:
  module TimestampConverter
    def self.from_json(parser : JSON::PullParser)
      time_str = parser.read_string

      begin
        Time::Format.new("%FT%T.%6N%:z").parse(time_str)
      rescue Time::Format::Error
        Time::Format.new("%FT%T%:z").parse(time_str)
      end
    end

    def self.to_json(value : Time, builder : JSON::Builder)
      Time::Format.new("%FT%T.%6N%:z").to_json(value, builder)
    end
  end

  # :nodoc:
  module MaybeTimestampConverter
    def self.from_json(parser : JSON::PullParser)
      if parser.kind.null?
        parser.read_null
        return nil
      end
      TimestampConverter.from_json(parser)
    end

    def self.to_json(value : Time?, builder : JSON::Builder)
      if value
        TimestampConverter.to_json(value, builder)
      else
        builder.null
      end
    end
  end

  # :nodoc:
  module TimeSpanMillisecondsConverter
    def self.from_json(parser : JSON::PullParser)
      parser.read_int.milliseconds
    end

    def self.to_json(value : Time::Span, builder : JSON::Builder)
      builder.scalar(value.milliseconds)
    end
  end

  # :nodoc:
  module AbstractCast
    macro included
      {% unless @type.abstract? %}
        {{ raise "AbstractCast can only be included in an abstract structure" }}
      {% end %}
      macro inherited
        {% verbatim do %}
          # Create a new instance of {{ @type }} from {{ @type.ancestors[0].id }}.
          # If {{ @type }} adds fields that can't be nil, it is are required to provide them as arguments
          def initialize(abst : {{ @type.ancestors[0].id }}, **args : **T) forall T
            {% verbatim do %}
              {% for field in @type.instance_vars %}
                {% if @type.ancestors[0].instance_vars.map(&.id).includes? field.id %}
                  @{{ field.name }} = abst.{{ field.name }}
                {% else %}
                  {% unless T.keys.includes? field.name.symbolize || field.has_default_value? %}
                    {{ raise "no argument '#{field.name}'" }}
                  {% end %}
                  @{{ field.name }} = args[{{ field.name.symbolize }}]
                {% end %}
              {% end %}
            {% end %}
          end
        {% end %}
      end
    end
  end
end
